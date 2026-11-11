import AppKit
import Darwin
import Foundation
import simd

public struct TelemetrySnapshot {
    public var cpuUsage: Float
    public var networkActivity: Float
    public var cursorUV: SIMD2<Float>
    public var cursorOnDesktopScreen: Bool

    public init(
        cpuUsage: Float = 0.05,
        networkActivity: Float = 0.0,
        cursorUV: SIMD2<Float> = SIMD2<Float>(0.5, 0.5),
        cursorOnDesktopScreen: Bool = true
    ) {
        self.cpuUsage = cpuUsage
        self.networkActivity = networkActivity
        self.cursorUV = cursorUV
        self.cursorOnDesktopScreen = cursorOnDesktopScreen
    }
}

public final class SystemTelemetrySampler {
    private var prevUserTicks: UInt64 = 0
    private var prevSysTicks: UInt64 = 0
    private var prevIdleTicks: UInt64 = 0
    private var prevNiceTicks: UInt64 = 0
    private var hasPrevCPU = false

    private var prevNetBytes: UInt64 = 0
    private var prevNetTimestamp: TimeInterval = 0
    private var hasPrevNet = false

    private var lastHeavySampleTime: TimeInterval = 0
    private var cachedCPU: Float = 0.06
    private var cachedNet: Float = 0.0

    public init() {}

    public func sample(now: TimeInterval, referenceFrame: CGRect?) -> TelemetrySnapshot {
        if now - lastHeavySampleTime >= 0.45 {
            lastHeavySampleTime = now
            cachedCPU = sampleCPULoad()
            cachedNet = sampleNetworkThroughput(now: now)
        }

        let mouse = NSEvent.mouseLocation
        let screenRect = referenceFrame ?? NSScreen.main?.frame ?? CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let u = Float((mouse.x - screenRect.minX) / max(screenRect.width, 1.0))
        let v = Float((mouse.y - screenRect.minY) / max(screenRect.height, 1.0))
        let clampedUV = SIMD2<Float>(
            min(max(u, 0.0), 1.0),
            min(max(v, 0.0), 1.0)
        )
        let inside = screenRect.contains(mouse)

        return TelemetrySnapshot(
            cpuUsage: cachedCPU,
            networkActivity: cachedNet,
            cursorUV: clampedUV,
            cursorOnDesktopScreen: inside
        )
    }

    private func sampleCPULoad() -> Float {
        var cpuInfo = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &cpuInfo) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPtr in
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, intPtr, &count)
            }
        }
        guard result == KERN_SUCCESS else { return cachedCPU }

        let user = UInt64(cpuInfo.cpu_ticks.0)
        let sys = UInt64(cpuInfo.cpu_ticks.1)
        let idle = UInt64(cpuInfo.cpu_ticks.2)
        let nice = UInt64(cpuInfo.cpu_ticks.3)

        defer {
            prevUserTicks = user
            prevSysTicks = sys
            prevIdleTicks = idle
            prevNiceTicks = nice
            hasPrevCPU = true
        }

        guard hasPrevCPU else { return 0.06 }

        let dUser = user >= prevUserTicks ? user - prevUserTicks : 0
        let dSys = sys >= prevSysTicks ? sys - prevSysTicks : 0
        let dIdle = idle >= prevIdleTicks ? idle - prevIdleTicks : 0
        let dNice = nice >= prevNiceTicks ? nice - prevNiceTicks : 0

        let total = dUser + dSys + dIdle + dNice
        guard total > 0 else { return cachedCPU }
        let busy = Float(dUser + dSys + dNice) / Float(total)
        return min(max(busy, 0.0), 1.0)
    }

    private func sampleNetworkThroughput(now: TimeInterval) -> Float {
        var ifaddrPtr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddrPtr) == 0, let firstAddr = ifaddrPtr else {
            return cachedNet * 0.85
        }
        defer { freeifaddrs(ifaddrPtr) }

        var totalBytes: UInt64 = 0
        var cursor: UnsafeMutablePointer<ifaddrs>? = firstAddr
        while let addr = cursor {
            let flags = Int32(addr.pointee.ifa_flags)
            let isUp = (flags & IFF_UP) != 0
            let isLoopback = (flags & IFF_LOOPBACK) != 0
            if isUp && !isLoopback,
               let sa = addr.pointee.ifa_addr,
               sa.pointee.sa_family == UInt8(AF_LINK),
               let data = addr.pointee.ifa_data {
                let netData = data.assumingMemoryBound(to: if_data.self)
                totalBytes &+= UInt64(netData.pointee.ifi_ibytes)
                totalBytes &+= UInt64(netData.pointee.ifi_obytes)
            }
            cursor = addr.pointee.ifa_next
        }

        defer {
            prevNetBytes = totalBytes
            prevNetTimestamp = now
            hasPrevNet = true
        }

        guard hasPrevNet, now > prevNetTimestamp, totalBytes >= prevNetBytes else {
            return 0.0
        }

        let dt = Float(now - prevNetTimestamp)
        let bytesPerSec = Float(totalBytes - prevNetBytes) / max(dt, 0.05)
        let normalized = log10(1.0 + bytesPerSec / 65_536.0) / 3.0
        return min(max(normalized, 0.0), 1.0)
    }
}
