import CoreVideo
import Foundation
import IOSurface
import Metal
import notify

public enum MimicBridgeProtocol {
    public static let frameNotifyName = "com.kavi.canopy.framebus"
    public static let subscriberNotifyName = "com.kavi.mimic.subscriber"

    public static func packFrame(surfaceID: UInt32, seq: UInt32) -> UInt64 {
        (UInt64(surfaceID) << 32) | UInt64(seq)
    }

    public static func unpackSubscriber(_ state: UInt64) -> (pid: pid_t, active: Bool, wantsFrames: Bool, coverage: Float)? {
        guard state != 0 else { return nil }
        let pid = pid_t(truncatingIfNeeded: state >> 32)
        let flags = (state >> 16) & 0xFFFF
        let permille = state & 0xFFFF
        return (
            pid: pid,
            active: (flags & 0x1) != 0,
            wantsFrames: (flags & 0x2) != 0,
            coverage: Float(permille) / 1000.0
        )
    }
}

public final class MimicBridge {
    private struct SharedSurface {
        let surface: IOSurfaceRef
        let id: UInt32
        let texture: MTLTexture
    }

    private let lock = NSLock()
    private var frameToken: Int32 = NOTIFY_TOKEN_INVALID
    private var subscriberCheckToken: Int32 = NOTIFY_TOKEN_INVALID
    private var subscriberDispatchToken: Int32 = NOTIFY_TOKEN_INVALID

    private var subscriberState: UInt64 = 0
    private var cachedSubscriber: (pid: pid_t, active: Bool, wantsFrames: Bool, coverage: Float)?
    private var lastWantsFrames = false
    private var seq: UInt32 = 0
    private var broadcasting = false

    private var pool: [SharedSurface] = []
    private var poolWidth = 0
    private var poolHeight = 0
    private var poolCursor = 0

    private var _needsKeyframe = true
    public var needsKeyframe: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _needsKeyframe
    }

    public init() {
        notify_register_check(MimicBridgeProtocol.frameNotifyName, &frameToken)
        if frameToken != NOTIFY_TOKEN_INVALID {
            notify_set_state(frameToken, 0)
            notify_post(MimicBridgeProtocol.frameNotifyName)
        }
        notify_register_check(MimicBridgeProtocol.subscriberNotifyName, &subscriberCheckToken)
        notify_register_dispatch(
            MimicBridgeProtocol.subscriberNotifyName,
            &subscriberDispatchToken,
            .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
        refresh()
    }

    deinit {
        if frameToken != NOTIFY_TOKEN_INVALID { notify_cancel(frameToken) }
        if subscriberCheckToken != NOTIFY_TOKEN_INVALID { notify_cancel(subscriberCheckToken) }
        if subscriberDispatchToken != NOTIFY_TOKEN_INVALID { notify_cancel(subscriberDispatchToken) }
    }

    public func refresh() {
        var state: UInt64 = 0
        if subscriberCheckToken != NOTIFY_TOKEN_INVALID {
            notify_get_state(subscriberCheckToken, &state)
        }
        lock.lock()
        subscriberState = state
        if let sub = MimicBridgeProtocol.unpackSubscriber(state),
           kill(sub.pid, 0) == 0 || errno == EPERM {
            cachedSubscriber = sub
        } else {
            cachedSubscriber = nil
        }
        let wants = cachedSubscriber?.wantsFrames ?? false
        if wants && !lastWantsFrames {
            _needsKeyframe = true
        }
        lastWantsFrames = wants
        lock.unlock()
    }

    public var coverageOverride: Float? {
        lock.lock()
        defer { lock.unlock() }
        guard let sub = cachedSubscriber, sub.active else { return nil }
        return sub.coverage
    }

    public var wantsFrames: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cachedSubscriber?.wantsFrames ?? false
    }

    public func nextTarget(device: MTLDevice, width: Int, height: Int) -> (texture: MTLTexture, surfaceID: UInt32)? {
        lock.lock()
        defer { lock.unlock() }
        if pool.isEmpty || poolWidth != width || poolHeight != height {
            pool = makePool(device: device, width: width, height: height)
            poolWidth = width
            poolHeight = height
            poolCursor = 0
            if !pool.isEmpty {
                _needsKeyframe = true
            }
        }
        guard !pool.isEmpty else { return nil }
        let entry = pool[poolCursor]
        poolCursor = (poolCursor + 1) % pool.count
        broadcasting = true
        return (entry.texture, entry.id)
    }

    /// Called from a Metal completion handler after the shared surface contains
    /// the latest frame; bumps the sequence and notifies subscribers.
    public func publish(surfaceID: UInt32) {
        lock.lock()
        seq &+= 1
        let state = MimicBridgeProtocol.packFrame(surfaceID: surfaceID, seq: seq)
        _needsKeyframe = false
        broadcasting = true
        lock.unlock()
        if frameToken != NOTIFY_TOKEN_INVALID {
            notify_set_state(frameToken, state)
        }
        notify_post(MimicBridgeProtocol.frameNotifyName)
    }

    public func stop() {
        lock.lock()
        guard broadcasting else {
            lock.unlock()
            return
        }
        broadcasting = false
        pool = []
        poolWidth = 0
        poolHeight = 0
        lock.unlock()
        if frameToken != NOTIFY_TOKEN_INVALID {
            notify_set_state(frameToken, 0)
        }
        notify_post(MimicBridgeProtocol.frameNotifyName)
    }

    private func makePool(device: MTLDevice, width: Int, height: Int) -> [SharedSurface] {
        var result: [SharedSurface] = []
        for _ in 0..<3 {
            let attrs: [CFString: Any] = [
                kIOSurfaceWidth: width,
                kIOSurfaceHeight: height,
                kIOSurfaceBytesPerElement: 4,
                kIOSurfacePixelFormat: kCVPixelFormatType_32BGRA,
                kIOSurfaceIsGlobal: true
            ]
            guard let surface = IOSurfaceCreate(attrs as CFDictionary) else { break }
            let id = IOSurfaceGetID(surface)
            let desc = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .bgra8Unorm,
                width: width,
                height: height,
                mipmapped: false
            )
            desc.usage = .shaderRead
            desc.storageMode = .shared
            guard let texture = device.makeTexture(descriptor: desc, iosurface: surface, plane: 0) else {
                continue
            }
            result.append(SharedSurface(surface: surface, id: id, texture: texture))
        }
        return result
    }
}
