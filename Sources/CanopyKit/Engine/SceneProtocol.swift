import Foundation
import Metal
import simd

public protocol MetalScene: AnyObject {
    var kind: SceneKind { get }
    var camera: CameraSetup { get }

    func encode(
        into commandBuffer: MTLCommandBuffer,
        renderPassDescriptor: MTLRenderPassDescriptor,
        uniformBuffer: MTLBuffer,
        impulseBuffer: MTLBuffer,
        viewportSize: SIMD2<Int>
    )
}
