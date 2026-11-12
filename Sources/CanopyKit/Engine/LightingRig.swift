import Foundation
import simd

public struct LightingState {
    public var sunDirection: SIMD3<Float>
    public var sunIntensity: Float
    public var sunColor: SIMD3<Float>
    public var solarWarmth: Float
    public var skyZenith: SIMD3<Float>
    public var fogDensity: Float
    public var skyHorizon: SIMD3<Float>
    public var exposure: Float
    public var groundBounce: SIMD3<Float>
    public var ambientStrength: Float

    public static func lerp(_ a: LightingState, _ b: LightingState, t: Float) -> LightingState {
        let k = min(max(t, 0.0), 1.0)
        let s = k * k * (3.0 - 2.0 * k)
        return LightingState(
            sunDirection: simd_normalize(simd_mix(a.sunDirection, b.sunDirection, SIMD3<Float>(repeating: s))),
            sunIntensity: a.sunIntensity + (b.sunIntensity - a.sunIntensity) * s,
            sunColor: simd_mix(a.sunColor, b.sunColor, SIMD3<Float>(repeating: s)),
            solarWarmth: a.solarWarmth + (b.solarWarmth - a.solarWarmth) * s,
            skyZenith: simd_mix(a.skyZenith, b.skyZenith, SIMD3<Float>(repeating: s)),
            fogDensity: a.fogDensity + (b.fogDensity - a.fogDensity) * s,
            skyHorizon: simd_mix(a.skyHorizon, b.skyHorizon, SIMD3<Float>(repeating: s)),
            exposure: a.exposure + (b.exposure - a.exposure) * s,
            groundBounce: simd_mix(a.groundBounce, b.groundBounce, SIMD3<Float>(repeating: s)),
            ambientStrength: a.ambientStrength + (b.ambientStrength - a.ambientStrength) * s
        )
    }
}

public final class LightingRig {
    private var current: LightingState?

    public init() {}

    public static let lightLush = LightingState(
        sunDirection: simd_normalize(SIMD3<Float>(0.55, 0.46, -0.70)),
        sunIntensity: 3.10,
        sunColor: SIMD3<Float>(1.04, 0.96, 0.82),
        solarWarmth: 0.90,
        skyZenith: SIMD3<Float>(0.085, 0.245, 0.620),
        fogDensity: 0.011,
        skyHorizon: SIMD3<Float>(0.420, 0.565, 0.740),
        exposure: 1.04,
        groundBounce: SIMD3<Float>(0.065, 0.115, 0.045),
        ambientStrength: 0.50
    )

    public static let goldenHour = LightingState(
        sunDirection: simd_normalize(SIMD3<Float>(0.68, 0.22, -0.70)),
        sunIntensity: 3.35,
        sunColor: SIMD3<Float>(1.08, 0.62, 0.28),
        solarWarmth: 0.56,
        skyZenith: SIMD3<Float>(0.070, 0.135, 0.300),
        fogDensity: 0.016,
        skyHorizon: SIMD3<Float>(0.620, 0.380, 0.210),
        exposure: 1.00,
        groundBounce: SIMD3<Float>(0.110, 0.085, 0.040),
        ambientStrength: 0.42
    )

    public static let dawnMist = LightingState(
        sunDirection: simd_normalize(SIMD3<Float>(-0.56, 0.24, -0.79)),
        sunIntensity: 2.35,
        sunColor: SIMD3<Float>(0.98, 0.78, 0.68),
        solarWarmth: 0.48,
        skyZenith: SIMD3<Float>(0.085, 0.180, 0.360),
        fogDensity: 0.020,
        skyHorizon: SIMD3<Float>(0.440, 0.450, 0.520),
        exposure: 0.98,
        groundBounce: SIMD3<Float>(0.055, 0.095, 0.080),
        ambientStrength: 0.46
    )

    public static let darkMoody = LightingState(
        sunDirection: simd_normalize(SIMD3<Float>(0.42, 0.48, -0.77)),
        sunIntensity: 1.20,
        sunColor: SIMD3<Float>(0.52, 0.70, 0.96),
        solarWarmth: 0.08,
        skyZenith: SIMD3<Float>(0.010, 0.022, 0.055),
        fogDensity: 0.018,
        skyHorizon: SIMD3<Float>(0.028, 0.055, 0.105),
        exposure: 0.86,
        groundBounce: SIMD3<Float>(0.014, 0.032, 0.038),
        ambientStrength: 0.28
    )

    public func evaluate(preset: LightingPreset, dt: Float, date: Date = Date()) -> LightingState {
        let target = Self.targetState(for: preset, date: date)
        guard let prev = current else {
            current = target
            return target
        }
        let blend = 1.0 - exp(-max(dt, 0.001) * 2.4)
        let next = LightingState.lerp(prev, target, t: blend)
        current = next
        return next
    }

    public static func targetState(for preset: LightingPreset, date: Date = Date()) -> LightingState {
        switch preset {
        case .lightLush:
            return lightLush
        case .goldenHour:
            return goldenHour
        case .darkMoody:
            return darkMoody
        case .autoSolar:
            return solarState(for: date)
        }
    }

    /// Real-sun lighting: tracks the true solar elevation at the resolved
    /// location (see `SolarCalculator`), so dawn, day length, and dusk follow
    /// the actual sky — including DST and seasonal shifts.
    public static func solarState(for date: Date) -> LightingState {
        let loc = SolarCalculator.currentLocation()
        return solarState(for: date, latitude: loc.latitude, longitude: loc.longitude)
    }

    public static func solarState(for date: Date, latitude: Double, longitude: Double) -> LightingState {
        let elev = SolarCalculator.solarElevation(at: date, latitude: latitude, longitude: longitude)
        return solarState(forElevation: Float(elev))
    }

    public static func solarState(forElevation elev: Float) -> LightingState {
        if elev < -8.0 {
            return darkMoody
        } else if elev < -2.0 {
            return .lerp(darkMoody, dawnMist, t: (elev + 8.0) / 6.0)
        } else if elev < 7.0 {
            return .lerp(dawnMist, goldenHour, t: (elev + 2.0) / 9.0)
        } else if elev < 24.0 {
            return .lerp(goldenHour, lightLush, t: (elev - 7.0) / 17.0)
        } else {
            return lightLush
        }
    }

    public static func solarState(forDecimalHour hour: Float) -> LightingState {
        let h = hour.truncatingRemainder(dividingBy: 24.0)
        if h < 5.5 {
            return darkMoody
        } else if h < 7.5 {
            return .lerp(darkMoody, dawnMist, t: (h - 5.5) / 2.0)
        } else if h < 9.5 {
            return .lerp(dawnMist, lightLush, t: (h - 7.5) / 2.0)
        } else if h < 16.5 {
            return lightLush
        } else if h < 19.0 {
            return .lerp(lightLush, goldenHour, t: (h - 16.5) / 2.5)
        } else if h < 21.0 {
            return .lerp(goldenHour, darkMoody, t: (h - 19.0) / 2.0)
        } else {
            return darkMoody
        }
    }
}
