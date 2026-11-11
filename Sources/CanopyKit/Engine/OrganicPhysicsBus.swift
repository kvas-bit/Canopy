import Foundation
import simd

public struct OrganicPhysicsState {
    public var windDirection: SIMD2<Float>
    public var windOffset: SIMD2<Float>
    public var baseWindSpeed: Float
    public var gustStrength: Float
    public var turbulence: Float
    public var smoothedCPULoad: Float
    public var smoothedNetBurst: Float
    public var cursorUV: SIMD2<Float>
    public var cursorVelocity: SIMD2<Float>
    public var cursorKineticEnergy: Float
    public var audioWindEnergy: Float
    public var audioRustleEnergy: Float
    public var impulses: [CursorImpulse]
}

public final class OrganicPhysicsBus {
    private var smoothedCPU: Float = 0.04
    private var smoothedNet: Float = 0.0
    private var windOffset: SIMD2<Float> = .zero

    private var prevCursorUV: SIMD2<Float>?
    private var smoothedCursorVel: SIMD2<Float> = .zero
    private var cursorKinetic: Float = 0.0
    private var lastImpulseSpawnPos: SIMD2<Float> = SIMD2<Float>(-10, -10)
    private var nextImpulseIndex: Int = 0
    private var impulses: [CursorImpulse] = Array(repeating: CursorImpulse(), count: CursorImpulse.maxCount)

    public init() {}

    public func step(
        dt rawDt: Float,
        elapsedTime: Float,
        telemetry: TelemetrySnapshot,
        windReactivityScale: Float,
        cursorReactivityScale: Float
    ) -> OrganicPhysicsState {
        let dt = min(max(rawDt, 1.0 / 240.0), 0.1)

        let cpuTau: Float = telemetry.cpuUsage > smoothedCPU ? 12.0 : 22.0
        let cpuAlpha = 1.0 - exp(-dt / cpuTau)
        smoothedCPU += (telemetry.cpuUsage - smoothedCPU) * cpuAlpha

        let netTau: Float = telemetry.networkActivity > smoothedNet ? 3.5 : 9.0
        let netAlpha = 1.0 - exp(-dt / netTau)
        smoothedNet += (telemetry.networkActivity - smoothedNet) * netAlpha

        let rawCursorVel: SIMD2<Float>
        if let prev = prevCursorUV {
            let delta = telemetry.cursorUV - prev
            if simd_length(delta) < 0.35 {
                rawCursorVel = delta / dt
            } else {
                rawCursorVel = .zero
            }
        } else {
            rawCursorVel = .zero
        }
        prevCursorUV = telemetry.cursorUV

        let velAlpha = 1.0 - exp(-dt * 14.0)
        smoothedCursorVel += (rawCursorVel - smoothedCursorVel) * velAlpha
        let speed = simd_length(smoothedCursorVel)
        let targetKinetic = min(speed * 0.65, 1.0)
        let kinAlpha = 1.0 - exp(-dt * (targetKinetic > cursorKinetic ? 10.0 : 2.8))
        cursorKinetic += (targetKinetic - cursorKinetic) * kinAlpha

        // Slow 40–90s natural breathing swells
        let naturalSwellA = sin(elapsedTime * 0.075) * 0.5 + 0.5
        let naturalSwellB = sin(elapsedTime * 0.145 + 1.7) * 0.5 + 0.5
        let naturalSquall = pow(naturalSwellA * 0.65 + naturalSwellB * 0.35, 1.5)

        // Subtract baseline ~5% idle OS noise so 95%+ idle CPU stays genuinely calm
        let activeCPU = max(smoothedCPU - 0.05, 0.0) / 0.95
        let cpuDrive = min(pow(activeCPU, 0.85) * windReactivityScale, 1.25)

        // Calm ~0.18 drift at idle; smoothly ramps up to ~0.58 under heavy CPU workloads
        let baseSpeed: Float = 0.16 + naturalSquall * 0.07 + cpuDrive * 0.36
        let gust: Float = (0.12 + naturalSquall * 0.16) * min(max(windReactivityScale, 0.25), 1.5) + cpuDrive * 0.48
        let turbulence: Float = 0.06 + cpuDrive * 0.28 + smoothedNet * 0.12

        let windHeadingAngle: Float = 0.18 + sin(elapsedTime * 0.025) * 0.08
        let windDir = simd_normalize(SIMD2<Float>(cos(windHeadingAngle), sin(windHeadingAngle)))

        // Proper time-integral of 2D wind velocity: d(windOffset)/dt == windDir * baseSpeed for ALL uptimes!
        windOffset += windDir * (dt * baseSpeed)
        if windOffset.x > 4096.0 { windOffset.x -= 4096.0 }
        if windOffset.y > 4096.0 { windOffset.y -= 4096.0 }

        let decayRate: Float = 0.32
        for i in 0..<CursorImpulse.maxCount {
            var imp = impulses[i]
            let strength = imp.velAndStrength.z
            if strength > 0.001 {
                var age = imp.posAndRadius.w + dt * decayRate
                if age >= 1.0 {
                    impulses[i] = CursorImpulse()
                } else {
                    var pos = SIMD2<Float>(imp.posAndRadius.x, imp.posAndRadius.y)
                    let vel = SIMD2<Float>(imp.velAndStrength.x, imp.velAndStrength.y)
                    pos += (vel * 0.05 + windDir * 0.018 * baseSpeed) * dt
                    let radius = imp.posAndRadius.z + dt * 0.032
                    let dampedStrength = strength * exp(-dt * 1.45)
                    age = min(age, 0.999)
                    imp.posAndRadius = SIMD4<Float>(pos.x, pos.y, radius, age)
                    imp.velAndStrength = SIMD4<Float>(vel.x, vel.y, dampedStrength, 0)
                    impulses[i] = imp
                }
            }
        }

        if cursorReactivityScale > 0.01 && telemetry.cursorOnDesktopScreen && speed > 0.07 {
            let distFromLast = simd_distance(telemetry.cursorUV, lastImpulseSpawnPos)
            if distFromLast > 0.028 {
                let impulseStrength = min(speed * 0.36, 0.85) * cursorReactivityScale
                let clampedVel = simd_length(smoothedCursorVel) > 2.0
                    ? simd_normalize(smoothedCursorVel) * 2.0
                    : smoothedCursorVel
                impulses[nextImpulseIndex] = CursorImpulse(
                    posAndRadius: SIMD4<Float>(telemetry.cursorUV.x, telemetry.cursorUV.y, 0.095, 0.0),
                    velAndStrength: SIMD4<Float>(clampedVel.x, clampedVel.y, impulseStrength, 0.0)
                )
                nextImpulseIndex = (nextImpulseIndex + 1) % CursorImpulse.maxCount
                lastImpulseSpawnPos = telemetry.cursorUV
            }
        }

        let audioWind = min(0.14 + gust * 0.55 + cpuDrive * 0.28, 1.0)
        let audioRustle = min(0.08 + turbulence * 0.45 + cursorKinetic * 0.45 * cursorReactivityScale, 1.0)

        return OrganicPhysicsState(
            windDirection: windDir,
            windOffset: windOffset,
            baseWindSpeed: baseSpeed,
            gustStrength: gust,
            turbulence: turbulence,
            smoothedCPULoad: smoothedCPU,
            smoothedNetBurst: smoothedNet,
            cursorUV: telemetry.cursorUV,
            cursorVelocity: smoothedCursorVel,
            cursorKineticEnergy: cursorKinetic,
            audioWindEnergy: audioWind,
            audioRustleEnergy: audioRustle,
            impulses: impulses
        )
    }

    public func injectSyntheticImpulse(uv: SIMD2<Float>, velocity: SIMD2<Float>, strength: Float = 0.85, radius: Float = 0.11) {
        impulses[nextImpulseIndex] = CursorImpulse(
            posAndRadius: SIMD4<Float>(uv.x, uv.y, radius, 0.05),
            velAndStrength: SIMD4<Float>(velocity.x, velocity.y, strength, 0.0)
        )
        nextImpulseIndex = (nextImpulseIndex + 1) % CursorImpulse.maxCount
    }
}
