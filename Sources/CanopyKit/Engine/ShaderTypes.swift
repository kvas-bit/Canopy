import Foundation
import simd

public enum SceneKind: Int, CaseIterable, Identifiable, Codable {
    case wildflowerMeadow = 0
    case wildMeadow = 4
    case mistyMoss = 1
    case forestStream = 2
    case coastalDunes = 3

    public var id: Int { rawValue }

    public var title: String {
        switch self {
        case .wildflowerMeadow: return "Grass-Swept Meadow"
        case .wildMeadow: return "Wild Meadow"
        case .mistyMoss: return "Misty Moss & Fern"
        case .forestStream: return "Forest Stream"
        case .coastalDunes: return "Coastal Dunes"
        }
    }

    public var subtitle: String {
        switch self {
        case .wildflowerMeadow: return "Lush emerald fescue, daisies & sky"
        case .wildMeadow: return "Seed plumes, buttercups & clover"
        case .mistyMoss: return "Redwood mist, sword ferns & grass"
        case .forestStream: return "Clear current, pebbles & caustics"
        case .coastalDunes: return "Sculpted sand & marram reeds"
        }
    }

    public var symbolName: String {
        switch self {
        case .wildflowerMeadow: return "leaf.fill"
        case .wildMeadow: return "camera.macro"
        case .mistyMoss: return "tree.fill"
        case .forestStream: return "drop.fill"
        case .coastalDunes: return "wind"
        }
    }
}

public enum LightingPreset: String, CaseIterable, Identifiable, Codable {
    case autoSolar = "auto"
    case lightLush = "lush"
    case goldenHour = "golden"
    case darkMoody = "dark"

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .autoSolar: return "Auto Solar"
        case .lightLush: return "Light Lush"
        case .goldenHour: return "Golden Hour"
        case .darkMoody: return "Dark Moody"
        }
    }

    public var symbolName: String {
        switch self {
        case .autoSolar: return "sun.and.horizon.fill"
        case .lightLush: return "sun.max.fill"
        case .goldenHour: return "sunset.fill"
        case .darkMoody: return "moon.stars.fill"
        }
    }
}

public enum FPSCapMode: String, CaseIterable, Identifiable, Codable {
    case adaptive = "adaptive"
    case cinematic30 = "30"
    case smooth60 = "60"

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .adaptive: return "Auto (24–30)"
        case .cinematic30: return "30 FPS"
        case .smooth60: return "60 FPS"
        }
    }
}

public struct CursorImpulse {
    public var posAndRadius: SIMD4<Float>
    public var velAndStrength: SIMD4<Float>

    public static let maxCount = 16

    public init(
        posAndRadius: SIMD4<Float> = .zero,
        velAndStrength: SIMD4<Float> = .zero
    ) {
        self.posAndRadius = posAndRadius
        self.velAndStrength = velAndStrength
    }
}

public struct FrameUniforms {
    public var viewProjMatrix: simd_float4x4
    public var invViewProjMatrix: simd_float4x4
    public var cameraPosAndFOV: SIMD4<Float>
    public var cameraForwardAndAspect: SIMD4<Float>
    public var cameraRightAndTime: SIMD4<Float>
    public var cameraUpAndDelta: SIMD4<Float>

    public var sunDirAndIntensity: SIMD4<Float>
    public var sunColorAndWarmth: SIMD4<Float>
    public var skyZenithAndFog: SIMD4<Float>
    public var skyHorizonAndExposure: SIMD4<Float>
    public var groundBounceAndAmbient: SIMD4<Float>

    public var windDirAndSpeed: SIMD4<Float>
    public var gustAndTurbulence: SIMD4<Float>
    public var cursorCurrent: SIMD4<Float>
    public var dofParams: SIMD4<Float>
    public var resolutionAndScene: SIMD4<Float>
    public var extraParams: SIMD4<Float>

    public init() {
        viewProjMatrix = matrix_identity_float4x4
        invViewProjMatrix = matrix_identity_float4x4
        cameraPosAndFOV = .zero
        cameraForwardAndAspect = .zero
        cameraRightAndTime = .zero
        cameraUpAndDelta = .zero
        sunDirAndIntensity = SIMD4<Float>(0, 1, 0, 1)
        sunColorAndWarmth = SIMD4<Float>(1, 1, 1, 1)
        skyZenithAndFog = .zero
        skyHorizonAndExposure = SIMD4<Float>(0, 0, 0, 1)
        groundBounceAndAmbient = .zero
        windDirAndSpeed = SIMD4<Float>(1, 0, 0, 1)
        gustAndTurbulence = .zero
        cursorCurrent = .zero
        dofParams = SIMD4<Float>(6.0, 2.5, 14.0, 1.0)
        resolutionAndScene = SIMD4<Float>(1920, 1080, 1.0 / 1920.0, 1.0 / 1080.0)
        extraParams = SIMD4<Float>(0, 1, 1, 1)
    }
}

public struct CameraSetup {
    public var position: SIMD3<Float>
    public var target: SIMD3<Float>
    public var up: SIMD3<Float>
    public var fovDegrees: Float
    public var nearZ: Float
    public var farZ: Float
    public var focusDistance: Float
    public var focusRange: Float
    public var baseBokehRadius: Float

    public init(
        position: SIMD3<Float>,
        target: SIMD3<Float>,
        up: SIMD3<Float> = SIMD3<Float>(0, 1, 0),
        fovDegrees: Float = 28.0,
        nearZ: Float = 0.25,
        farZ: Float = 85.0,
        focusDistance: Float = 6.2,
        focusRange: Float = 2.4,
        baseBokehRadius: Float = 15.0
    ) {
        self.position = position
        self.target = target
        self.up = up
        self.fovDegrees = fovDegrees
        self.nearZ = nearZ
        self.farZ = farZ
        self.focusDistance = focusDistance
        self.focusRange = focusRange
        self.baseBokehRadius = baseBokehRadius
    }
}

public enum Math3D {
    public static func perspectiveMetalRH(fovYRadians: Float, aspect: Float, nearZ: Float, farZ: Float) -> simd_float4x4 {
        let ys = 1.0 / tan(fovYRadians * 0.5)
        let xs = ys / max(aspect, 0.001)
        let zs = farZ / (nearZ - farZ)
        return simd_float4x4(columns: (
            SIMD4<Float>(xs, 0, 0, 0),
            SIMD4<Float>(0, ys, 0, 0),
            SIMD4<Float>(0, 0, zs, -1),
            SIMD4<Float>(0, 0, zs * nearZ, 0)
        ))
    }

    public static func lookAtRH(eye: SIMD3<Float>, target: SIMD3<Float>, up: SIMD3<Float>) -> (
        matrix: simd_float4x4,
        forward: SIMD3<Float>,
        right: SIMD3<Float>,
        trueUp: SIMD3<Float>
    ) {
        let zAxis = simd_normalize(eye - target)
        let xAxis = simd_normalize(simd_cross(up, zAxis))
        let yAxis = simd_cross(zAxis, xAxis)
        let mat = simd_float4x4(columns: (
            SIMD4<Float>(xAxis.x, yAxis.x, zAxis.x, 0),
            SIMD4<Float>(xAxis.y, yAxis.y, zAxis.y, 0),
            SIMD4<Float>(xAxis.z, yAxis.z, zAxis.z, 0),
            SIMD4<Float>(-simd_dot(xAxis, eye), -simd_dot(yAxis, eye), -simd_dot(zAxis, eye), 1)
        ))
        return (mat, -zAxis, xAxis, yAxis)
    }
}
