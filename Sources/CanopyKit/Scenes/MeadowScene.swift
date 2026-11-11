import Foundation
import Metal
import simd

public final class MeadowScene: MetalScene {
    public let kind: SceneKind = .wildflowerMeadow
    public let camera: CameraSetup

    private let backdropPipeline: MTLRenderPipelineState
    private let terrainPipeline: MTLRenderPipelineState
    private let grassPipeline: MTLRenderPipelineState
    private let flowerPipeline: MTLRenderPipelineState
    private let seedPipeline: MTLRenderPipelineState

    private let depthAlwaysNoWrite: MTLDepthStencilState
    private let depthReadWrite: MTLDepthStencilState
    private let depthReadOnly: MTLDepthStencilState

    public let grassBladeCount = 84_480
    public let flowerCount = 3_200
    public let seedCount = 90

    public init(device: MTLDevice, library: MTLLibrary) throws {
        self.camera = CameraSetup(
            position: SIMD3<Float>(-0.08, 1.00, 4.55),
            target: SIMD3<Float>(0.60, 0.68, -1.55),
            up: SIMD3<Float>(0, 1, 0),
            fovDegrees: 23.0,
            nearZ: 0.25,
            farZ: 75.0,
            focusDistance: 4.95,
            focusRange: 1.95,
            baseBokehRadius: 15.0
        )

        let bgDesc = MTLRenderPipelineDescriptor()
        bgDesc.label = "Meadow.Backdrop"
        bgDesc.rasterSampleCount = MetalRenderer.msaaSampleCount
        bgDesc.vertexFunction = library.makeFunction(name: "meadowBackdropVertex")
        bgDesc.fragmentFunction = library.makeFunction(name: "meadowBackdropFragment")
        bgDesc.colorAttachments[0].pixelFormat = .rgba16Float
        bgDesc.depthAttachmentPixelFormat = .depth32Float
        self.backdropPipeline = try device.makeRenderPipelineState(descriptor: bgDesc)

        let terrainDesc = MTLRenderPipelineDescriptor()
        terrainDesc.label = "Meadow.Terrain"
        terrainDesc.rasterSampleCount = MetalRenderer.msaaSampleCount
        terrainDesc.vertexFunction = library.makeFunction(name: "meadowTerrainVertex")
        terrainDesc.fragmentFunction = library.makeFunction(name: "meadowTerrainFragment")
        terrainDesc.colorAttachments[0].pixelFormat = .rgba16Float
        terrainDesc.depthAttachmentPixelFormat = .depth32Float
        self.terrainPipeline = try device.makeRenderPipelineState(descriptor: terrainDesc)

        let grassDesc = MTLRenderPipelineDescriptor()
        grassDesc.label = "Meadow.Grass"
        grassDesc.rasterSampleCount = MetalRenderer.msaaSampleCount
        grassDesc.vertexFunction = library.makeFunction(name: "meadowGrassVertex")
        grassDesc.fragmentFunction = library.makeFunction(name: "meadowGrassFragment")
        grassDesc.colorAttachments[0].pixelFormat = .rgba16Float
        grassDesc.depthAttachmentPixelFormat = .depth32Float
        self.grassPipeline = try device.makeRenderPipelineState(descriptor: grassDesc)

        let flowerDesc = MTLRenderPipelineDescriptor()
        flowerDesc.label = "Meadow.Wildflowers"
        flowerDesc.rasterSampleCount = MetalRenderer.msaaSampleCount
        flowerDesc.vertexFunction = library.makeFunction(name: "meadowFlowerVertex")
        flowerDesc.fragmentFunction = library.makeFunction(name: "meadowFlowerFragment")
        flowerDesc.colorAttachments[0].pixelFormat = .rgba16Float
        flowerDesc.depthAttachmentPixelFormat = .depth32Float
        self.flowerPipeline = try device.makeRenderPipelineState(descriptor: flowerDesc)

        let seedDesc = MTLRenderPipelineDescriptor()
        seedDesc.label = "Meadow.Seeds"
        seedDesc.rasterSampleCount = MetalRenderer.msaaSampleCount
        seedDesc.vertexFunction = library.makeFunction(name: "meadowSeedVertex")
        seedDesc.fragmentFunction = library.makeFunction(name: "meadowSeedFragment")
        seedDesc.colorAttachments[0].pixelFormat = .rgba16Float
        seedDesc.colorAttachments[0].isBlendingEnabled = true
        seedDesc.colorAttachments[0].rgbBlendOperation = .add
        seedDesc.colorAttachments[0].sourceRGBBlendFactor = .one
        seedDesc.colorAttachments[0].destinationRGBBlendFactor = .one
        seedDesc.colorAttachments[0].alphaBlendOperation = .add
        seedDesc.colorAttachments[0].sourceAlphaBlendFactor = .zero
        seedDesc.colorAttachments[0].destinationAlphaBlendFactor = .one
        seedDesc.depthAttachmentPixelFormat = .depth32Float
        self.seedPipeline = try device.makeRenderPipelineState(descriptor: seedDesc)

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
        enc.label = "Canopy.MeadowScene"

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
        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 96 * 96 * 6)

        enc.setRenderPipelineState(grassPipeline)
        enc.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 15, instanceCount: grassBladeCount)

        enc.setRenderPipelineState(flowerPipeline)
        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6, instanceCount: flowerCount)

        enc.setDepthStencilState(depthReadOnly)
        enc.setRenderPipelineState(seedPipeline)
        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6, instanceCount: seedCount)

        enc.endEncoding()
    }
}
