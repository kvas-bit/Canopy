import AVFoundation
import Foundation
import os.lock

public final class WindAudioEngine {
    private struct SynthParams {
        var targetGain: Float = 0.0
        var windEnergy: Float = 0.25
        var rustleEnergy: Float = 0.15
        var sceneKind: Int32 = 0
    }

    private final class SynthState: @unchecked Sendable {
        var lock = os_unfair_lock_s()
        var params = SynthParams()

        var rngL: UInt32 = 0x1234_5678
        var rngR: UInt32 = 0x9ABC_DEF1

        var pinkL: (Float, Float, Float) = (0, 0, 0)
        var pinkR: (Float, Float, Float) = (0, 0, 0)

        var lowBandL: Float = 0
        var lowLpL: Float = 0
        var lowBandR: Float = 0
        var lowLpR: Float = 0

        var highBandL: Float = 0
        var highLpL: Float = 0
        var highBandR: Float = 0
        var highLpR: Float = 0

        var smoothGain: Float = 0
        var smoothWind: Float = 0.25
        var smoothRustle: Float = 0.15
        var lfoPhase: Float = 0
    }

    private let state = SynthState()
    private var engine: AVAudioEngine?
    private var sourceNode: AVAudioSourceNode?
    private var isRunning = false

    public init() {}

    public func update(
        enabled: Bool,
        paused: Bool,
        volume: Float,
        windEnergy: Float,
        rustleEnergy: Float,
        scene: SceneKind
    ) {
        let shouldPlay = enabled && !paused && volume > 0.005

        os_unfair_lock_lock(&state.lock)
        state.params.targetGain = shouldPlay ? min(max(volume, 0.0), 1.0) * 0.22 : 0.0
        state.params.windEnergy = min(max(windEnergy, 0.0), 1.0)
        state.params.rustleEnergy = min(max(rustleEnergy, 0.0), 1.0)
        state.params.sceneKind = Int32(scene.rawValue)
        os_unfair_lock_unlock(&state.lock)

        if shouldPlay && !isRunning {
            startEngineIfNeeded()
        } else if !shouldPlay && isRunning {
            stopEngine()
        }
    }

    public func shutdown() {
        stopEngine()
    }

    private func startEngineIfNeeded() {
        if engine == nil {
            let avEngine = AVAudioEngine()
            let sampleRate = avEngine.outputNode.outputFormat(forBus: 0).sampleRate
            let sr = Float(sampleRate > 8000 ? sampleRate : 48_000)
            guard let format = AVAudioFormat(standardFormatWithSampleRate: Double(sr), channels: 2) else {
                return
            }

            let captured = state
            let node = AVAudioSourceNode(format: format) { _, _, frameCount, audioBufferList -> OSStatus in
                let abl = UnsafeMutableAudioBufferListPointer(audioBufferList)
                guard abl.count >= 2,
                      let outL = abl[0].mData?.assumingMemoryBound(to: Float.self),
                      let outR = abl[1].mData?.assumingMemoryBound(to: Float.self) else {
                    return noErr
                }

                os_unfair_lock_lock(&captured.lock)
                let p = captured.params
                os_unfair_lock_unlock(&captured.lock)

                let frames = Int(frameCount)
                let invSR = 1.0 / sr

                for i in 0..<frames {
                    captured.smoothGain += (p.targetGain - captured.smoothGain) * 0.0006
                    captured.smoothWind += (p.windEnergy - captured.smoothWind) * 0.00025
                    captured.smoothRustle += (p.rustleEnergy - captured.smoothRustle) * 0.00045

                    captured.rngL = captured.rngL &* 1664525 &+ 1013904223
                    captured.rngR = captured.rngR &* 22695477 &+ 1
                    let whiteL = Float(Int32(bitPattern: captured.rngL)) / Float(Int32.max)
                    let whiteR = Float(Int32(bitPattern: captured.rngR)) / Float(Int32.max)

                    captured.pinkL.0 = 0.99765 * captured.pinkL.0 + whiteL * 0.0990460
                    captured.pinkL.1 = 0.96300 * captured.pinkL.1 + whiteL * 0.2965164
                    captured.pinkL.2 = 0.57000 * captured.pinkL.2 + whiteL * 1.0526913
                    let pinkSampleL = (captured.pinkL.0 + captured.pinkL.1 + captured.pinkL.2 + whiteL * 0.1848) * 0.22

                    captured.pinkR.0 = 0.99765 * captured.pinkR.0 + whiteR * 0.0990460
                    captured.pinkR.1 = 0.96300 * captured.pinkR.1 + whiteR * 0.2965164
                    captured.pinkR.2 = 0.57000 * captured.pinkR.2 + whiteR * 1.0526913
                    let pinkSampleR = (captured.pinkR.0 + captured.pinkR.1 + captured.pinkR.2 + whiteR * 0.1848) * 0.22

                    captured.lfoPhase += invSR * (0.14 + captured.smoothWind * 0.22)
                    if captured.lfoPhase > 1.0 { captured.lfoPhase -= 1.0 }
                    let swell = sin(captured.lfoPhase * 6.2831853) * 0.5 + 0.5

                    let lowCutoff: Float
                    let highCutoff: Float
                    let lowQ: Float
                    let highMix: Float

                    switch p.sceneKind {
                    case 1:
                        lowCutoff = 135.0 + captured.smoothWind * 140.0 + swell * 35.0
                        highCutoff = 850.0 + captured.smoothRustle * 900.0
                        lowQ = 0.42
                        highMix = 0.22
                    case 2:
                        let rippleMod = sin(captured.lfoPhase * 37.699) * 190.0
                        lowCutoff = 220.0 + captured.smoothWind * 160.0
                        highCutoff = max(620.0, 1180.0 + captured.smoothRustle * 1100.0 + rippleMod)
                        lowQ = 0.58
                        highMix = 0.46
                    case 3:
                        lowCutoff = 190.0 + captured.smoothWind * 250.0 + swell * 55.0
                        highCutoff = 1650.0 + captured.smoothRustle * 1850.0
                        lowQ = 0.36
                        highMix = 0.40
                    default:
                        lowCutoff = 165.0 + captured.smoothWind * 210.0 + swell * 45.0
                        highCutoff = 1350.0 + captured.smoothRustle * 1750.0
                        lowQ = 0.38
                        highMix = 0.36
                    }

                    let fLow = min(2.0 * sin(.pi * lowCutoff * invSR), 0.75)
                    let hpLowL = pinkSampleL - captured.lowLpL - lowQ * captured.lowBandL
                    captured.lowBandL += fLow * hpLowL
                    captured.lowLpL += fLow * captured.lowBandL

                    let hpLowR = pinkSampleR - captured.lowLpR - lowQ * captured.lowBandR
                    captured.lowBandR += fLow * hpLowR
                    captured.lowLpR += fLow * captured.lowBandR

                    let fHigh = min(2.0 * sin(.pi * highCutoff * invSR), 0.85)
                    let hpHighL = whiteL * 0.35 - captured.highLpL - 0.65 * captured.highBandL
                    captured.highBandL += fHigh * hpHighL
                    captured.highLpL += fHigh * captured.highBandL

                    let hpHighR = whiteR * 0.35 - captured.highLpR - 0.65 * captured.highBandR
                    captured.highBandR += fHigh * hpHighR
                    captured.highLpR += fHigh * captured.highBandR

                    let bodyGain = 0.45 + 0.65 * captured.smoothWind
                    let rustleGain = highMix * (0.25 + 0.85 * captured.smoothRustle)

                    outL[i] = (captured.lowBandL * bodyGain + captured.highBandL * rustleGain) * captured.smoothGain
                    outR[i] = (captured.lowBandR * bodyGain + captured.highBandR * rustleGain) * captured.smoothGain
                }
                return noErr
            }

            avEngine.attach(node)
            avEngine.connect(node, to: avEngine.mainMixerNode, format: format)
            self.engine = avEngine
            self.sourceNode = node
        }

        do {
            try engine?.start()
            isRunning = true
        } catch {
            isRunning = false
        }
    }

    private func stopEngine() {
        engine?.stop()
        isRunning = false
    }
}
