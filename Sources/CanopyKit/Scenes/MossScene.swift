import Foundation
import Metal
import simd

public final class MossScene: MetalScene {
    public let kind: SceneKind = .mistyMoss
    public let camera: CameraSetup

    private let backdropPipeline: MTLRenderPipelineState
    private let trunkPipeline: MTLRenderPipelineState
    private let terrainPipeline: MTLRenderPipelineState
    private let grassPipeline: MTLRenderPipelineState
    private let fernPipeline: MTLRenderPipelineState
    private let sporePipeline: MTLRenderPipelineState

    private let depthAlwaysNoWrite: MTLDepthStencilState
    private let depthReadWrite: MTLDepthStencilState
    private let depthReadOnly: MTLDepthStencilState

    public let trunkCount = 28
    public let grassCount = 61_600
    public let fernFrondCount = 1_960
    public let dustMoteCount = 90

    public init(device: MTLDevice, library: MTLLibrary) throws {
        self.camera = CameraSetup(
            position: SIMD3<Float>(0.0, 0.92, 4.35),
            target: SIMD3<Float>(0.05, 0.72, -3.20),
            up: SIMD3<Float>(0, 1, 0),
            fovDegrees: 27.0,
            nearZ: 0.25,
            farZ: 55.0,
            focusDistance: 5.10,
            focusRange: 2.65,
            baseBokehRadius: 12.0
        )

        let bgDesc = MTLRenderPipelineDescriptor()
        bgDesc.label = "Moss.Backdrop"
        bgDesc.rasterSampleCount = MetalRenderer.msaaSampleCount
        bgDesc.vertexFunction = library.makeFunction(name: "mossBackdropVertex")
        bgDesc.fragmentFunction = library.makeFunction(name: "mossBackdropFragment")
        bgDesc.colorAttachments[0].pixelFormat = .rgba16Float
        bgDesc.depthAttachmentPixelFormat = .depth32Float
        self.backdropPipeline = try device.makeRenderPipelineState(descriptor: bgDesc)

        let trunkDesc = MTLRenderPipelineDescriptor()
        trunkDesc.label = "Moss.Trunks"
        trunkDesc.rasterSampleCount = MetalRenderer.msaaSampleCount
        trunkDesc.vertexFunction = library.makeFunction(name: "mossTrunkVertex")
        trunkDesc.fragmentFunction = library.makeFunction(name: "mossTrunkFragment")
        trunkDesc.colorAttachments[0].pixelFormat = .rgba16Float
        trunkDesc.depthAttachmentPixelFormat = .depth32Float
        self.trunkPipeline = try device.makeRenderPipelineState(descriptor: trunkDesc)

        let terDesc = MTLRenderPipelineDescriptor()
        terDesc.label = "Moss.Terrain"
        terDesc.rasterSampleCount = MetalRenderer.msaaSampleCount
        terDesc.vertexFunction = library.makeFunction(name: "mossTerrainVertex")
        terDesc.fragmentFunction = library.makeFunction(name: "mossTerrainFragment")
        terDesc.colorAttachments[0].pixelFormat = .rgba16Float
        terDesc.depthAttachmentPixelFormat = .depth32Float
        self.terrainPipeline = try device.makeRenderPipelineState(descriptor: terDesc)

        let grassDesc = MTLRenderPipelineDescriptor()
        grassDesc.label = "Moss.WoodlandGrass"
        grassDesc.rasterSampleCount = MetalRenderer.msaaSampleCount
        grassDesc.vertexFunction = library.makeFunction(name: "mossGrassVertex")
        grassDesc.fragmentFunction = library.makeFunction(name: "mossGrassFragment")
        grassDesc.colorAttachments[0].pixelFormat = .rgba16Float
        grassDesc.depthAttachmentPixelFormat = .depth32Float
        self.grassPipeline = try device.makeRenderPipelineState(descriptor: grassDesc)

        let fernDesc = MTLRenderPipelineDescriptor()
        fernDesc.label = "Moss.SwordFerns"
        fernDesc.rasterSampleCount = MetalRenderer.msaaSampleCount
        fernDesc.vertexFunction = library.makeFunction(name: "mossFernVertex")
        fernDesc.fragmentFunction = library.makeFunction(name: "mossFernFragment")
        fernDesc.colorAttachments[0].pixelFormat = .rgba16Float
        fernDesc.depthAttachmentPixelFormat = .depth32Float
        self.fernPipeline = try device.makeRenderPipelineState(descriptor: fernDesc)

        let sporeDesc = MTLRenderPipelineDescriptor()
        sporeDesc.label = "Moss.DustMotes"
        sporeDesc.rasterSampleCount = MetalRenderer.msaaSampleCount
        sporeDesc.vertexFunction = library.makeFunction(name: "mossSporeVertex")
        sporeDesc.fragmentFunction = library.makeFunction(name: "mossSporeFragment")
        sporeDesc.colorAttachments[0].pixelFormat = .rgba16Float
        sporeDesc.colorAttachments[0].isBlendingEnabled = true
        sporeDesc.colorAttachments[0].rgbBlendOperation = .add
        sporeDesc.colorAttachments[0].sourceRGBBlendFactor = .one
        sporeDesc.colorAttachments[0].destinationRGBBlendFactor = .one
        sporeDesc.colorAttachments[0].alphaBlendOperation = .add
        sporeDesc.colorAttachments[0].sourceAlphaBlendFactor = .zero
        sporeDesc.colorAttachments[0].destinationAlphaBlendFactor = .one
        sporeDesc.depthAttachmentPixelFormat = .depth32Float
        self.sporePipeline = try device.makeRenderPipelineState(descriptor: sporeDesc)

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
        enc.label = "Canopy.MossScene"

        enc.setVertexBuffer(uniformBuffer, offset: 0, index: 0)
        enc.setVertexBuffer(impulseBuffer, offset: 0, index: 1)
        enc.setFragmentBuffer(uniformBuffer, offset: 0, index: 0)
        enc.setFragmentBuffer(impulseBuffer, offset: 0, index: 1)

        enc.setDepthStencilState(depthAlwaysNoWrite)
        enc.setRenderPipelineState(backdropPipeline)
        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)

        enc.setDepthStencilState(depthReadWrite)
        enc.setCullMode(.none)

        enc.setRenderPipelineState(trunkPipeline)
        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 12 * 6 * 6, instanceCount: trunkCount)

        enc.setRenderPipelineState(terrainPipeline)
        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 104 * 104 * 6)

        enc.setRenderPipelineState(grassPipeline)
        enc.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 13, instanceCount: grassCount)

        enc.setRenderPipelineState(fernPipeline)
        enc.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 17, instanceCount: fernFrondCount)

        enc.setDepthStencilState(depthReadOnly)
        enc.setRenderPipelineState(sporePipeline)
        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6, instanceCount: dustMoteCount)

        enc.endEncoding()
    }
}
