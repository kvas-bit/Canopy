import Foundation
import Metal
import simd

public final class StreamScene: MetalScene {
    public let kind: SceneKind = .forestStream
    public let camera: CameraSetup

    private let surfacePipeline: MTLRenderPipelineState
    private let leafPipeline: MTLRenderPipelineState
    private let depthReadWrite: MTLDepthStencilState

    public let leafCount = 26

    public init(device: MTLDevice, library: MTLLibrary) throws {
        self.camera = CameraSetup(
            position: SIMD3<Float>(0.0, 2.35, 3.35),
            target: SIMD3<Float>(0.10, -0.18, -0.95),
            up: SIMD3<Float>(0, 1, 0),
            fovDegrees: 25.0,
            nearZ: 0.25,
            farZ: 45.0,
            focusDistance: 4.15,
            focusRange: 1.45,
            baseBokehRadius: 15.5
        )

        let surfDesc = MTLRenderPipelineDescriptor()
        surfDesc.label = "Stream.WaterSurface"
        surfDesc.rasterSampleCount = MetalRenderer.msaaSampleCount
        surfDesc.vertexFunction = library.makeFunction(name: "streamSurfaceVertex")
        surfDesc.fragmentFunction = library.makeFunction(name: "streamSurfaceFragment")
        surfDesc.colorAttachments[0].pixelFormat = .rgba16Float
        surfDesc.depthAttachmentPixelFormat = .depth32Float
        self.surfacePipeline = try device.makeRenderPipelineState(descriptor: surfDesc)

        let leafDesc = MTLRenderPipelineDescriptor()
        leafDesc.label = "Stream.FloatingLeaves"
        leafDesc.rasterSampleCount = MetalRenderer.msaaSampleCount
        leafDesc.vertexFunction = library.makeFunction(name: "streamLeafVertex")
        leafDesc.fragmentFunction = library.makeFunction(name: "streamLeafFragment")
        leafDesc.colorAttachments[0].pixelFormat = .rgba16Float
        leafDesc.depthAttachmentPixelFormat = .depth32Float
        self.leafPipeline = try device.makeRenderPipelineState(descriptor: leafDesc)

        let dRW = MTLDepthStencilDescriptor()
        dRW.depthCompareFunction = .lessEqual
        dRW.isDepthWriteEnabled = true
        self.depthReadWrite = device.makeDepthStencilState(descriptor: dRW)!
    }

    public func encode(
        into commandBuffer: MTLCommandBuffer,
        renderPassDescriptor: MTLRenderPassDescriptor,
        uniformBuffer: MTLBuffer,
        impulseBuffer: MTLBuffer,
        viewportSize: SIMD2<Int>
    ) {
        guard let enc = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else { return }
        enc.label = "Canopy.StreamScene"

        enc.setVertexBuffer(uniformBuffer, offset: 0, index: 0)
        enc.setVertexBuffer(impulseBuffer, offset: 0, index: 1)
        enc.setFragmentBuffer(uniformBuffer, offset: 0, index: 0)
        enc.setFragmentBuffer(impulseBuffer, offset: 0, index: 1)

        enc.setDepthStencilState(depthReadWrite)
        enc.setCullMode(.none)

        enc.setRenderPipelineState(surfacePipeline)
        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 128 * 128 * 6)

        enc.setRenderPipelineState(leafPipeline)
        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6, instanceCount: leafCount)

        enc.endEncoding()
    }
}
