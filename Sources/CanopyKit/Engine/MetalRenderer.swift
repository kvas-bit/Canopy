import Foundation
import Metal
import QuartzCore
import simd

public final class MetalRenderer {
    public static let maxFramesInFlight = 3
    public static let msaaSampleCount = 4

    public let device: MTLDevice
    public let commandQueue: MTLCommandQueue
    public let library: MTLLibrary

    private let frameSemaphore = DispatchSemaphore(value: MetalRenderer.maxFramesInFlight)
    private var frameSlot: Int = 0
    private var uniformBuffers: [MTLBuffer] = []
    private var impulseBuffers: [MTLBuffer] = []

    private let postPipeline: MTLRenderPipelineState
    private var scenes: [SceneKind: MetalScene] = [:]

    private struct OffscreenTargets {
        let width: Int
        let height: Int
        let msaaColor: MTLTexture
        let msaaDepth: MTLTexture
        let hdrResolved: MTLTexture
        let depthResolved: MTLTexture
    }
    private var cachedTargetsBySize: [SIMD2<Int>: OffscreenTargets] = [:]

    public init(device: MTLDevice? = nil, scenes builder: (MTLDevice, MTLLibrary) throws -> [MetalScene]) throws {
        guard let dev = device ?? MTLCreateSystemDefaultDevice() else {
            throw NSError(domain: "Canopy.MetalRenderer", code: 1, userInfo: [NSLocalizedDescriptionKey: "Metal device unavailable"])
        }
        guard let queue = dev.makeCommandQueue() else {
            throw NSError(domain: "Canopy.MetalRenderer", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to create MTLCommandQueue"])
        }
        self.device = dev
        self.commandQueue = queue
        self.library = try MetalShaderLibraryLoader.loadLibrary(device: dev)

        for _ in 0..<Self.maxFramesInFlight {
            guard let uBuf = dev.makeBuffer(length: MemoryLayout<FrameUniforms>.stride, options: .storageModeShared),
                  let iBuf = dev.makeBuffer(length: MemoryLayout<CursorImpulse>.stride * CursorImpulse.maxCount, options: .storageModeShared) else {
                throw NSError(domain: "Canopy.MetalRenderer", code: 3, userInfo: [NSLocalizedDescriptionKey: "Failed to allocate uniform buffers"])
            }
            uniformBuffers.append(uBuf)
            impulseBuffers.append(iBuf)
        }

        let postDesc = MTLRenderPipelineDescriptor()
        postDesc.label = "Canopy.PostProcessBokeh"
        postDesc.vertexFunction = library.makeFunction(name: "postProcessVertex")
        postDesc.fragmentFunction = library.makeFunction(name: "postProcessFragment")
        postDesc.colorAttachments[0].pixelFormat = .bgra8Unorm
        self.postPipeline = try dev.makeRenderPipelineState(descriptor: postDesc)

        let builtScenes = try builder(dev, library)
        for s in builtScenes {
            scenes[s.kind] = s
        }
    }

    public func registerScene(_ scene: MetalScene) {
        scenes[scene.kind] = scene
    }

    public func scene(for kind: SceneKind) -> MetalScene? {
        scenes[kind]
    }

    public func renderToDrawable(
        layer: CAMetalLayer,
        sceneKind: SceneKind,
        elapsedTime: Float,
        dt: Float,
        physics: OrganicPhysicsState,
        lighting: LightingState,
        apertureScale: Float,
        cursorScale: Float,
        windScale: Float,
        broadcast: MimicBridge? = nil
    ) {
        guard frameSemaphore.wait(timeout: .now()) == .success else { return }

        guard let drawable = layer.nextDrawable() else {
            frameSemaphore.signal()
            return
        }

        let outTex = drawable.texture
        guard let commandBuffer = commandQueue.makeCommandBuffer() else {
            frameSemaphore.signal()
            return
        }

        let sema = frameSemaphore
        commandBuffer.addCompletedHandler { _ in
            sema.signal()
        }

        encodeFrame(
            into: commandBuffer,
            destinationTexture: outTex,
            sceneKind: sceneKind,
            elapsedTime: elapsedTime,
            dt: dt,
            physics: physics,
            lighting: lighting,
            apertureScale: apertureScale,
            cursorScale: cursorScale,
            windScale: windScale
        )

        if let broadcast, !outTex.isFramebufferOnly,
           let target = broadcast.nextTarget(device: device, width: outTex.width, height: outTex.height),
           let blit = commandBuffer.makeBlitCommandEncoder() {
            blit.copy(
                from: outTex,
                sourceSlice: 0,
                sourceLevel: 0,
                sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
                sourceSize: MTLSize(width: outTex.width, height: outTex.height, depth: 1),
                to: target.texture,
                destinationSlice: 0,
                destinationLevel: 0,
                destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0)
            )
            blit.endEncoding()
            let surfaceID = target.surfaceID
            commandBuffer.addCompletedHandler { _ in
                broadcast.publish(surfaceID: surfaceID)
            }
        }

        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    public func renderToTexture(
        destinationTexture: MTLTexture,
        sceneKind: SceneKind,
        elapsedTime: Float,
        dt: Float,
        physics: OrganicPhysicsState,
        lighting: LightingState,
        apertureScale: Float,
        cursorScale: Float,
        windScale: Float
    ) {
        guard let commandBuffer = commandQueue.makeCommandBuffer() else { return }
        encodeFrame(
            into: commandBuffer,
            destinationTexture: destinationTexture,
            sceneKind: sceneKind,
            elapsedTime: elapsedTime,
            dt: dt,
            physics: physics,
            lighting: lighting,
            apertureScale: apertureScale,
            cursorScale: cursorScale,
            windScale: windScale
        )
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
    }

    private func encodeFrame(
        into commandBuffer: MTLCommandBuffer,
        destinationTexture: MTLTexture,
        sceneKind: SceneKind,
        elapsedTime: Float,
        dt: Float,
        physics: OrganicPhysicsState,
        lighting: LightingState,
        apertureScale: Float,
        cursorScale: Float,
        windScale: Float
    ) {
        guard let activeScene = scenes[sceneKind] else { return }

        let width = max(destinationTexture.width, 16)
        let height = max(destinationTexture.height, 16)
        guard let targets = ensureTargets(width: width, height: height) else { return }

        let uBuf = uniformBuffers[frameSlot]
        let iBuf = impulseBuffers[frameSlot]
        frameSlot = (frameSlot + 1) % Self.maxFramesInFlight

        var uniforms = buildUniforms(
            camera: activeScene.camera,
            width: width,
            height: height,
            sceneKind: sceneKind,
            elapsedTime: elapsedTime,
            dt: dt,
            physics: physics,
            lighting: lighting,
            apertureScale: apertureScale,
            cursorScale: cursorScale,
            windScale: windScale
        )
        memcpy(uBuf.contents(), &uniforms, MemoryLayout<FrameUniforms>.stride)

        physics.impulses.withUnsafeBytes { rawPtr in
            if let base = rawPtr.baseAddress {
                memcpy(iBuf.contents(), base, min(rawPtr.count, iBuf.length))
            }
        }

        let scenePass = MTLRenderPassDescriptor()
        scenePass.colorAttachments[0].texture = targets.msaaColor
        scenePass.colorAttachments[0].resolveTexture = targets.hdrResolved
        scenePass.colorAttachments[0].loadAction = .clear
        scenePass.colorAttachments[0].storeAction = .multisampleResolve
        scenePass.colorAttachments[0].clearColor = MTLClearColor(
            red: Double(lighting.skyHorizon.x),
            green: Double(lighting.skyHorizon.y),
            blue: Double(lighting.skyHorizon.z),
            alpha: Double(activeScene.camera.farZ)
        )

        scenePass.depthAttachment.texture = targets.msaaDepth
        scenePass.depthAttachment.resolveTexture = targets.depthResolved
        scenePass.depthAttachment.depthResolveFilter = .min
        scenePass.depthAttachment.loadAction = .clear
        scenePass.depthAttachment.storeAction = .multisampleResolve
        scenePass.depthAttachment.clearDepth = 1.0

        activeScene.encode(
            into: commandBuffer,
            renderPassDescriptor: scenePass,
            uniformBuffer: uBuf,
            impulseBuffer: iBuf,
            viewportSize: SIMD2<Int>(width, height)
        )

        let postPass = MTLRenderPassDescriptor()
        postPass.colorAttachments[0].texture = destinationTexture
        postPass.colorAttachments[0].loadAction = .dontCare
        postPass.colorAttachments[0].storeAction = .store

        if let postEnc = commandBuffer.makeRenderCommandEncoder(descriptor: postPass) {
            postEnc.label = "Canopy.BokehPostPass"
            postEnc.setRenderPipelineState(postPipeline)
            postEnc.setFragmentTexture(targets.hdrResolved, index: 0)
            postEnc.setFragmentTexture(targets.depthResolved, index: 1)
            postEnc.setFragmentBuffer(uBuf, offset: 0, index: 0)
            postEnc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
            postEnc.endEncoding()
        }
    }

    private func ensureTargets(width: Int, height: Int) -> OffscreenTargets? {
        let key = SIMD2<Int>(width, height)
        if let existing = cachedTargetsBySize[key] {
            return existing
        }
        if cachedTargetsBySize.count >= 3 {
            cachedTargetsBySize.removeAll(keepingCapacity: true)
        }

        let msaaColorDesc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba16Float,
            width: width,
            height: height,
            mipmapped: false
        )
        msaaColorDesc.textureType = .type2DMultisample
        msaaColorDesc.sampleCount = Self.msaaSampleCount
        msaaColorDesc.storageMode = .memoryless
        msaaColorDesc.usage = .renderTarget

        let msaaDepthDesc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .depth32Float,
            width: width,
            height: height,
            mipmapped: false
        )
        msaaDepthDesc.textureType = .type2DMultisample
        msaaDepthDesc.sampleCount = Self.msaaSampleCount
        msaaDepthDesc.storageMode = .memoryless
        msaaDepthDesc.usage = .renderTarget

        let hdrDesc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba16Float,
            width: width,
            height: height,
            mipmapped: false
        )
        hdrDesc.storageMode = .private
        hdrDesc.usage = [.renderTarget, .shaderRead]

        let depthResolvedDesc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .depth32Float,
            width: width,
            height: height,
            mipmapped: false
        )
        depthResolvedDesc.storageMode = .private
        depthResolvedDesc.usage = [.renderTarget, .shaderRead]

        guard let msaaColor = device.makeTexture(descriptor: msaaColorDesc),
              let msaaDepth = device.makeTexture(descriptor: msaaDepthDesc),
              let hdrResolved = device.makeTexture(descriptor: hdrDesc),
              let depthResolved = device.makeTexture(descriptor: depthResolvedDesc) else {
            return nil
        }

        let created = OffscreenTargets(
            width: width,
            height: height,
            msaaColor: msaaColor,
            msaaDepth: msaaDepth,
            hdrResolved: hdrResolved,
            depthResolved: depthResolved
        )
        cachedTargetsBySize[key] = created
        return created
    }

    private func buildUniforms(
        camera: CameraSetup,
        width: Int,
        height: Int,
        sceneKind: SceneKind,
        elapsedTime: Float,
        dt: Float,
        physics: OrganicPhysicsState,
        lighting: LightingState,
        apertureScale: Float,
        cursorScale: Float,
        windScale: Float
    ) -> FrameUniforms {
        let aspect = Float(width) / max(Float(height), 1.0)
        let fovRad = camera.fovDegrees * (.pi / 180.0)
        let camPos = camera.position

        let look = Math3D.lookAtRH(eye: camPos, target: camera.target, up: camera.up)
        let proj = Math3D.perspectiveMetalRH(
            fovYRadians: fovRad,
            aspect: aspect,
            nearZ: camera.nearZ,
            farZ: camera.farZ
        )
        let vp = proj * look.matrix
        let invVP = vp.inverse

        let resolutionScale = Float(height) / 1080.0
        var u = FrameUniforms()
        u.viewProjMatrix = vp
        u.invViewProjMatrix = invVP
        u.cameraPosAndFOV = SIMD4<Float>(camPos.x, camPos.y, camPos.z, tan(fovRad * 0.5))
        u.cameraForwardAndAspect = SIMD4<Float>(look.forward.x, look.forward.y, look.forward.z, aspect)
        u.cameraRightAndTime = SIMD4<Float>(look.right.x, look.right.y, look.right.z, elapsedTime)
        u.cameraUpAndDelta = SIMD4<Float>(look.trueUp.x, look.trueUp.y, look.trueUp.z, dt)

        u.sunDirAndIntensity = SIMD4<Float>(
            lighting.sunDirection.x,
            lighting.sunDirection.y,
            lighting.sunDirection.z,
            lighting.sunIntensity
        )
        u.sunColorAndWarmth = SIMD4<Float>(
            lighting.sunColor.x,
            lighting.sunColor.y,
            lighting.sunColor.z,
            lighting.solarWarmth
        )
        u.skyZenithAndFog = SIMD4<Float>(
            lighting.skyZenith.x,
            lighting.skyZenith.y,
            lighting.skyZenith.z,
            lighting.fogDensity
        )
        u.skyHorizonAndExposure = SIMD4<Float>(
            lighting.skyHorizon.x,
            lighting.skyHorizon.y,
            lighting.skyHorizon.z,
            lighting.exposure
        )
        u.groundBounceAndAmbient = SIMD4<Float>(
            lighting.groundBounce.x,
            lighting.groundBounce.y,
            lighting.groundBounce.z,
            lighting.ambientStrength
        )

        u.windDirAndSpeed = SIMD4<Float>(
            physics.windDirection.x,
            physics.windDirection.y,
            physics.windOffset.x,
            physics.windOffset.y
        )
        u.gustAndTurbulence = SIMD4<Float>(
            physics.gustStrength,
            physics.turbulence,
            physics.smoothedCPULoad,
            physics.smoothedNetBurst
        )
        u.cursorCurrent = SIMD4<Float>(
            physics.cursorUV.x,
            physics.cursorUV.y,
            physics.cursorVelocity.x,
            physics.cursorVelocity.y
        )
        u.dofParams = SIMD4<Float>(
            camera.focusDistance,
            camera.focusRange,
            camera.baseBokehRadius * resolutionScale,
            apertureScale
        )
        u.resolutionAndScene = SIMD4<Float>(
            Float(width),
            Float(height),
            1.0 / Float(width),
            1.0 / Float(height)
        )
        u.extraParams = SIMD4<Float>(
            Float(sceneKind.rawValue),
            cursorScale,
            camera.nearZ,
            camera.farZ
        )
        return u
    }
}
