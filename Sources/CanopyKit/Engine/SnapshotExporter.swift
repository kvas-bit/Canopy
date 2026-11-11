import CoreGraphics
import Foundation
import ImageIO
import Metal
import UniformTypeIdentifiers
import simd

public enum SnapshotExporter {
    public static func renderSnapshotPNG(
        renderer: MetalRenderer,
        scene: SceneKind,
        lightingPreset: LightingPreset,
        width: Int = 1600,
        height: Int = 1000,
        elapsedTime: Float = 14.5,
        cpuLoad: Float = 0.28,
        outputURL: URL
    ) throws {
        let texDesc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: width,
            height: height,
            mipmapped: false
        )
        texDesc.storageMode = .shared
        texDesc.usage = [.renderTarget, .shaderRead]

        guard let outTex = renderer.device.makeTexture(descriptor: texDesc) else {
            throw NSError(domain: "Canopy.Snapshot", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to allocate snapshot texture"])
        }

        let bus = OrganicPhysicsBus()
        let snap = TelemetrySnapshot(
            cpuUsage: cpuLoad,
            networkActivity: 0.25,
            cursorUV: SIMD2<Float>(0.54, 0.46),
            cursorOnDesktopScreen: true
        )
        var state = bus.step(dt: 0.033, elapsedTime: elapsedTime - 0.1, telemetry: snap, windReactivityScale: 1.0, cursorReactivityScale: 1.0)
        bus.injectSyntheticImpulse(uv: SIMD2<Float>(0.48, 0.44), velocity: SIMD2<Float>(0.85, 0.28), strength: 0.72, radius: 0.12)
        state = bus.step(dt: 0.033, elapsedTime: elapsedTime, telemetry: snap, windReactivityScale: 1.0, cursorReactivityScale: 1.0)

        let lighting = LightingRig.targetState(for: lightingPreset)

        renderer.renderToTexture(
            destinationTexture: outTex,
            sceneKind: scene,
            elapsedTime: elapsedTime,
            dt: 0.033,
            physics: state,
            lighting: lighting,
            apertureScale: 1.0,
            cursorScale: 1.0,
            windScale: 1.0
        )

        let bytesPerRow = width * 4
        var rawBytes = [UInt8](repeating: 0, count: bytesPerRow * height)
        outTex.getBytes(
            &rawBytes,
            bytesPerRow: bytesPerRow,
            from: MTLRegionMake2D(0, 0, width, height),
            mipmapLevel: 0
        )

        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        let bitmapInfo = CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue
        guard let provider = CGDataProvider(data: Data(rawBytes) as CFData),
              let cgImage = CGImage(
                  width: width,
                  height: height,
                  bitsPerComponent: 8,
                  bitsPerPixel: 32,
                  bytesPerRow: bytesPerRow,
                  space: colorSpace,
                  bitmapInfo: CGBitmapInfo(rawValue: bitmapInfo),
                  provider: provider,
                  decode: nil,
                  shouldInterpolate: false,
                  intent: .defaultIntent
              ),
              let dest = CGImageDestinationCreateWithURL(outputURL as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw NSError(domain: "Canopy.Snapshot", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to encode PNG"])
        }

        CGImageDestinationAddImage(dest, cgImage, nil)
        guard CGImageDestinationFinalize(dest) else {
            throw NSError(domain: "Canopy.Snapshot", code: 3, userInfo: [NSLocalizedDescriptionKey: "Failed to finalize PNG write"])
        }
    }
}
