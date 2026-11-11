import AppKit
import CoreGraphics
import Foundation

public struct PowerStatus: Equatable {
    public var isRenderingPaused: Bool
    public var pauseReason: String?
    public var targetFPS: Int
    public var desktopCoverage: Float

    public init(
        isRenderingPaused: Bool = false,
        pauseReason: String? = nil,
        targetFPS: Int = 30,
        desktopCoverage: Float = 0.0
    ) {
        self.isRenderingPaused = isRenderingPaused
        self.pauseReason = pauseReason
        self.targetFPS = targetFPS
        self.desktopCoverage = desktopCoverage
    }
}

public final class PowerCoordinator {
    private var isDisplayAsleep = false
    private var lastOcclusionCheck: TimeInterval = 0
    private var cachedCoverage: Float = 0.0
    private let ownPID: pid_t = ProcessInfo.processInfo.processIdentifier

    public init() {}

    public func setDisplayAsleep(_ asleep: Bool) {
        isDisplayAsleep = asleep
    }

    public func evaluate(
        now: TimeInterval,
        userPaused: Bool,
        pauseWhenOccluded: Bool,
        previewWindowVisible: Bool,
        fpsMode: FPSCapMode,
        cursorKineticEnergy: Float,
        gustStrength: Float
    ) -> PowerStatus {
        if userPaused {
            return PowerStatus(isRenderingPaused: true, pauseReason: "Paused", targetFPS: 0, desktopCoverage: cachedCoverage)
        }
        if isDisplayAsleep {
            return PowerStatus(isRenderingPaused: true, pauseReason: "Display Asleep", targetFPS: 0, desktopCoverage: cachedCoverage)
        }
        if ProcessInfo.processInfo.isLowPowerModeEnabled && !previewWindowVisible {
            return PowerStatus(isRenderingPaused: true, pauseReason: "Low Power Mode", targetFPS: 0, desktopCoverage: cachedCoverage)
        }

        if now - lastOcclusionCheck >= 0.65 {
            lastOcclusionCheck = now
            cachedCoverage = Self.estimateDesktopOcclusion(excludingPID: ownPID)
        }

        if pauseWhenOccluded && !previewWindowVisible && cachedCoverage >= 0.92 {
            return PowerStatus(
                isRenderingPaused: true,
                pauseReason: "Desktop Covered",
                targetFPS: 0,
                desktopCoverage: cachedCoverage
            )
        }

        let fps: Int
        switch fpsMode {
        case .cinematic30:
            fps = 30
        case .smooth60:
            fps = 60
        case .adaptive:
            fps = cursorKineticEnergy > 0.12 ? 30 : 24
        }

        return PowerStatus(
            isRenderingPaused: false,
            pauseReason: nil,
            targetFPS: fps,
            desktopCoverage: cachedCoverage
        )
    }

    public static func estimateDesktopOcclusion(excludingPID: pid_t) -> Float {
        let screens = NSScreen.screens
        guard !screens.isEmpty else { return 0.0 }

        guard let infoList = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else {
            return 0.0
        }

        let primaryHeight = screens[0].frame.height
        var windowRects: [CGRect] = []
        windowRects.reserveCapacity(infoList.count)

        for entry in infoList {
            guard let pid = entry[kCGWindowOwnerPID as String] as? pid_t, pid != excludingPID else { continue }
            guard let layer = entry[kCGWindowLayer as String] as? Int, layer == 0 else { continue }
            let alpha = (entry[kCGWindowAlpha as String] as? Double) ?? 1.0
            guard alpha >= 0.85 else { continue }
            guard let boundsDict = entry[kCGWindowBounds as String] as? NSDictionary,
                  let cgRect = CGRect(dictionaryRepresentation: boundsDict),
                  cgRect.width > 120, cgRect.height > 120 else {
                continue
            }
            let appKitY = primaryHeight - cgRect.origin.y - cgRect.height
            windowRects.append(CGRect(x: cgRect.origin.x, y: appKitY, width: cgRect.width, height: cgRect.height))
        }

        guard !windowRects.isEmpty else { return 0.0 }

        let cols = 16
        let rows = 10
        var minUnoccludedScreenCoverage: Float = 1.0

        for screen in screens {
            let sFrame = screen.visibleFrame
            guard sFrame.width > 1, sFrame.height > 1 else { continue }
            let cellW = sFrame.width / CGFloat(cols)
            let cellH = sFrame.height / CGFloat(rows)
            var coveredCount = 0

            for r in 0..<rows {
                for c in 0..<cols {
                    let probe = CGPoint(
                        x: sFrame.minX + (CGFloat(c) + 0.5) * cellW,
                        y: sFrame.minY + (CGFloat(r) + 0.5) * cellH
                    )
                    if windowRects.contains(where: { $0.contains(probe) }) {
                        coveredCount += 1
                    }
                }
            }
            let screenCoverage = Float(coveredCount) / Float(cols * rows)
            minUnoccludedScreenCoverage = min(minUnoccludedScreenCoverage, screenCoverage)
        }

        return minUnoccludedScreenCoverage
    }
}
