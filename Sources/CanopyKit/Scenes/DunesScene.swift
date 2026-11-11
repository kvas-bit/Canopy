import Foundation
import Metal
import simd

public final class DunesScene: MetalScene {
    public let kind: SceneKind = .coastalDunes
    public let camera: CameraSetup

    private let backdropPipeline: MTLRenderPipelineState
    private let terrainPipeline: MTLRenderPipelineState
    private let reedPipeline: MTLRenderPipelineState
    private let mistPipeline: MTLRenderPipelineState

    private let depthAlwaysNoWrite: MTLDepthStencilState
    private let depthReadWrite: MTLDepthStencilState
    private let depthReadOnly: MTLDepthStencilState

    public let reedCount = 23_800
    public let sandMistCount = 200

    public init(device: MTLDevice, library: MTLLibrary) throws {
        self.camera = CameraSetup(
            position: SIMD3<Float>(-0.25, 1.12, 4.45),
            target: SIMD3<Float>(0.22, 0.58, -1.85),
            up: SIMD3<Float>(0, 1, 0),
            fovDegrees: 24.0,
            nearZ: 0.25,
            farZ: 65.0,
            focusDistance: 4.75,
            focusRange: 2.35,
            baseBokehRadius: 11.5
        )

        let bgDesc = MTLRenderPipelineDescriptor()
        bgDesc.label = "Dunes.Backdrop"
        bgDesc.rasterSampleCount = MetalRenderer.msaaSampleCount
        bgDesc.vertexFunction = library.makeFunction(name: "duneBackdropVertex")
        bgDesc.fragmentFunction = library.makeFunction(name: "duneBackdropFragment")
        bgDesc.colorAttachments[0].pixelFormat = .rgba16Float
        bgDesc.depthAttachmentPixelFormat = .depth32Float
        self.backdropPipeline = try device.makeRenderPipelineState(descriptor: bgDesc)

        let terDesc = MTLRenderPipelineDescriptor()
        terDesc.label = "Dunes.Terrain"
        terDesc.rasterSampleCount = MetalRenderer.msaaSampleCount
        terDesc.vertexFunction = library.makeFunction(name: "duneTerrainVertex")
        terDesc.fragmentFunction = library.makeFunction(name: "duneTerrainFragment")
        terDesc.colorAttachments[0].pixelFormat = .rgba16Float
        terDesc.depthAttachmentPixelFormat = .depth32Float
        self.terrainPipeline = try device.makeRenderPipelineState(descriptor: terDesc)

        let reedDesc = MTLRenderPipelineDescriptor()
        reedDesc.label = "Dunes.Reeds"
        reedDesc.rasterSampleCount = MetalRenderer.msaaSampleCount
        reedDesc.vertexFunction = library.makeFunction(name: "duneReedVertex")
        reedDesc.fragmentFunction = library.makeFunction(name: "duneReedFragment")
        reedDesc.colorAttachments[0].pixelFormat = .rgba16Float
        reedDesc.depthAttachmentPixelFormat = .depth32Float
        self.reedPipeline = try device.makeRenderPipelineState(descriptor: reedDesc)

        let mistDesc = MTLRenderPipelineDescriptor()
        mistDesc.label = "Dunes.SandMist"
        mistDesc.rasterSampleCount = MetalRenderer.msaaSampleCount
        mistDesc.vertexFunction = library.makeFunction(name: "duneSandMistVertex")
        mistDesc.fragmentFunction = library.makeFunction(name: "duneSandMistFragment")
        mistDesc.colorAttachments[0].pixelFormat = .rgba16Float
        mistDesc.colorAttachments[0].isBlendingEnabled = true
        mistDesc.colorAttachments[0].rgbBlendOperation = .add
        mistDesc.colorAttachments[0].sourceRGBBlendFactor = .one
        mistDesc.colorAttachments[0].destinationRGBBlendFactor = .one
        mistDesc.colorAttachments[0].alphaBlendOperation = .add
        mistDesc.colorAttachments[0].sourceAlphaBlendFactor = .zero
        mistDesc.colorAttachments[0].destinationAlphaBlendFactor = .one
        mistDesc.depthAttachmentPixelFormat = .depth32Float
        self.mistPipeline = try device.makeRenderPipelineState(descriptor: mistDesc)

        let dBg = MTLDepthStencilDescriptor()
        dBg.depthCompareFunction = .always
        dBg.isDepthWriteEnabled = false
        self.depthAlwaysNoWrite = device.makeDepthStencilState(descriptor: dBg)!

        let dRW = MTLDepthStencilDescriptor()
        dRW.depthCompareFunction = .lessEqual
        dRW.isDepthWriteEnabled = true
        self.depthReadWrite = device.makeDepthStencilState(descriptor: dRW)!

        let dRO = MTLDepthStencilDescriptor()
        dRO.depthCompareFunction = .lessEqual
        dRO.isDepthWriteEnabled = false
        self.depthReadOnly = device.makeDepthStencilState(descriptor: dRO)!
    }

    public func encode(
        into commandBuffer: MTLCommandBuffer,
        renderPassDescriptor: MTLRenderPassDescriptor,
        uniformBuffer: MTLBuffer,
        impulseBuffer: MTLBuffer,
        viewportSize: SIMD2<Int>
    ) {
        guard let enc = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else { return }
        enc.label = "Canopy.DunesScene"

        enc.setVertexBuffer(uniformBuffer, offset: 0, index: 0)
        enc.setVertexBuffer(impulseBuffer, offset: 0, index: 1)
        enc.setFragmentBuffer(uniformBuffer, offset: 0, index: 0)
        enc.setFragmentBuffer(impulseBuffer, offset: 0, index: 1)

        enc.setDepthStencilState(depthAlwaysNoWrite)
        enc.setRenderPipelineState(backdropPipeline)
        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)

        enc.setDepthStencilState(depthReadWrite)
        enc.setCullMode(.none)
        enc.setRenderPipelineState(terrainPipeline)
        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 140 * 140 * 6)

        enc.setRenderPipelineState(reedPipeline)
        enc.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 15, instanceCount: reedCount)

        enc.setDepthStencilState(depthReadOnly)
        enc.setRenderPipelineState(mistPipeline)
        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6, instanceCount: sandMistCount)

        enc.endEncoding()
    }
}
