import AppKit
import Combine
import Foundation
import QuartzCore

@MainActor
public final class CanopyController: ObservableObject {
    @Published public var selectedScene: SceneKind {
        didSet { defaults.set(selectedScene.rawValue, forKey: "scene") }
    }
    @Published public var lightingPreset: LightingPreset {
        didSet { defaults.set(lightingPreset.rawValue, forKey: "lighting") }
    }
    @Published public var fpsMode: FPSCapMode {
        didSet {
            defaults.set(fpsMode.rawValue, forKey: "fpsMode")
            rescheduleTimerIfNeeded()
        }
    }
    @Published public var windReactivity: Double {
        didSet { defaults.set(windReactivity, forKey: "windReactivity") }
    }
    @Published public var cursorReactivity: Double {
        didSet { defaults.set(cursorReactivity, forKey: "cursorReactivity") }
    }
    @Published public var bokehDepth: Double {
        didSet { defaults.set(bokehDepth, forKey: "bokehDepth") }
    }
    @Published public var pauseWhenOccluded: Bool {
        didSet { defaults.set(pauseWhenOccluded, forKey: "pauseWhenOccluded") }
    }
    @Published public var userPaused: Bool = false
    @Published public var desktopWallpaperEnabled: Bool {
        didSet {
            defaults.set(desktopWallpaperEnabled, forKey: "desktopEnabled")
            windowManager.setDesktopEnabled(desktopWallpaperEnabled)
            if !desktopWallpaperEnabled {
                bridge.stop()
            }
        }
    }
    @Published public var audioEnabled: Bool {
        didSet { defaults.set(audioEnabled, forKey: "audioEnabled") }
    }
    @Published public var audioVolume: Double {
        didSet { defaults.set(audioVolume, forKey: "audioVolume") }
    }

    @Published public private(set) var isPreviewOpen: Bool = false
    @Published public private(set) var statusSummary: String = "30 FPS"
    @Published public private(set) var isCurrentlyPaused: Bool = false
    @Published public private(set) var cpuPercent: Int = 5

    /// e.g. "☀︎ 6:31 AM → ☾ 4:22 PM · New York" — lets the Auto Solar row
    /// cross-reference today's computed sun times against the real sky.
    public var solarSummary: String {
        SolarCalculator.summary()
    }

    public let renderer: MetalRenderer
    public let windowManager: DesktopWindowManager

    private let defaults = UserDefaults.standard
    private let telemetrySampler = SystemTelemetrySampler()
    private let physicsBus = OrganicPhysicsBus()
    private let lightingRig = LightingRig()
    private let powerCoordinator = PowerCoordinator()
    private let audioEngine = WindAudioEngine()
    private let bridge = MimicBridge()

    private var timer: DispatchSourceTimer?
    private var currentTimerFPS: Int = 0
    private var startTimestamp: CFTimeInterval = CACurrentMediaTime()
    private var lastFrameTimestamp: CFTimeInterval = CACurrentMediaTime()
    private var prevSelfCPUTime: Double = 0
    private var prevSelfSampleWall: CFTimeInterval = 0
    private var cachedSelfCPUPercent: Double = 0.8
    private var lastBridgeRefresh: CFTimeInterval = 0

    public init() throws {
        let renderer = try Self.makeDefaultRenderer()
        self.renderer = renderer
        self.windowManager = DesktopWindowManager(device: renderer.device)

        let rawScene = UserDefaults.standard.object(forKey: "scene") as? Int ?? SceneKind.wildflowerMeadow.rawValue
        self.selectedScene = SceneKind(rawValue: rawScene) ?? .wildflowerMeadow

        let rawLight = UserDefaults.standard.string(forKey: "lighting") ?? LightingPreset.lightLush.rawValue
        self.lightingPreset = LightingPreset(rawValue: rawLight) ?? .lightLush

        let rawFPS = UserDefaults.standard.string(forKey: "fpsMode") ?? FPSCapMode.adaptive.rawValue
        self.fpsMode = FPSCapMode(rawValue: rawFPS) ?? .adaptive

        self.windReactivity = UserDefaults.standard.object(forKey: "windReactivity") as? Double ?? 1.0
        self.cursorReactivity = UserDefaults.standard.object(forKey: "cursorReactivity") as? Double ?? 1.0
        self.bokehDepth = UserDefaults.standard.object(forKey: "bokehDepth") as? Double ?? 1.0
        self.pauseWhenOccluded = UserDefaults.standard.object(forKey: "pauseWhenOccluded") as? Bool ?? true
        self.desktopWallpaperEnabled = UserDefaults.standard.object(forKey: "desktopEnabled") as? Bool ?? true
        self.audioEnabled = UserDefaults.standard.object(forKey: "audioEnabled") as? Bool ?? false
        self.audioVolume = UserDefaults.standard.object(forKey: "audioVolume") as? Double ?? 0.45

        windowManager.onPreviewVisibilityChanged = { [weak self] visible in
            self?.isPreviewOpen = visible
        }

        registerWorkspaceNotifications()
    }

    nonisolated public static func makeDefaultRenderer() throws -> MetalRenderer {
        try MetalRenderer { device, library in
            [
                try MeadowScene(device: device, library: library),
                try WildMeadowScene(device: device, library: library),
                try MossScene(device: device, library: library),
                try StreamScene(device: device, library: library),
                try DunesScene(device: device, library: library)
            ]
        }
    }

    public func start() {
        windowManager.setDesktopEnabled(desktopWallpaperEnabled)
        startTimestamp = CACurrentMediaTime()
        lastFrameTimestamp = startTimestamp
        scheduleRenderLoop(fps: 30)
    }

    public func togglePreview() {
        windowManager.togglePreviewWindow()
        isPreviewOpen = windowManager.isPreviewVisible
    }

    public func shutdown() {
        timer?.cancel()
        timer = nil
        audioEngine.shutdown()
        bridge.stop()
    }

    private func registerWorkspaceNotifications() {
        let ws = NSWorkspace.shared.notificationCenter
        ws.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.powerCoordinator.setDisplayAsleep(true)
            }
        }
        ws.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.powerCoordinator.setDisplayAsleep(false)
            }
        }
    }

    private func scheduleRenderLoop(fps: Int) {
        let clampedFPS = max(fps, 2)
        guard clampedFPS != currentTimerFPS || timer == nil else { return }
        currentTimerFPS = clampedFPS

        timer?.cancel()
        let t = DispatchSource.makeTimerSource(queue: .main)
        let interval = 1.0 / Double(clampedFPS)
        t.schedule(deadline: .now(), repeating: interval, leeway: .milliseconds(3))
        t.setEventHandler { [weak self] in
            self?.tickFrame()
        }
        t.resume()
        timer = t
    }

    private func rescheduleTimerIfNeeded() {
        if !isCurrentlyPaused {
            scheduleRenderLoop(fps: fpsMode == .smooth60 ? 60 : 30)
        }
    }

    private func tickFrame() {
        let now = CACurrentMediaTime()
        let dt = Float(min(max(now - lastFrameTimestamp, 1.0 / 120.0), 0.1))
        lastFrameTimestamp = now
        let elapsed = Float(now - startTimestamp)

        let refFrame = windowManager.previewScreenFrame ?? NSScreen.main?.frame
        let telemetry = telemetrySampler.sample(now: now, referenceFrame: refFrame)

        let physics = physicsBus.step(
            dt: dt,
            elapsedTime: elapsed,
            telemetry: telemetry,
            windReactivityScale: Float(windReactivity),
            cursorReactivityScale: Float(cursorReactivity)
        )

        if now - lastBridgeRefresh >= 0.5 {
            lastBridgeRefresh = now
            bridge.refresh()
        }
        let wantsFrames = bridge.wantsFrames && windowManager.primaryDesktopLayer != nil
        windowManager.setPrimaryDesktopReadback(wantsFrames)
        if !wantsFrames {
            bridge.stop()
        }

        let power = powerCoordinator.evaluate(
            now: now,
            userPaused: userPaused,
            pauseWhenOccluded: pauseWhenOccluded,
            previewWindowVisible: windowManager.isPreviewVisible,
            fpsMode: fpsMode,
            cursorKineticEnergy: physics.cursorKineticEnergy,
            gustStrength: physics.gustStrength,
            coverageOverride: bridge.coverageOverride
        )

        let desktopCovered = pauseWhenOccluded && power.desktopCoverage >= 0.92
        let layers = windowManager.activeTargetLayers(skipDesktop: desktopCovered)
        let effectivelyPaused = power.isRenderingPaused || layers.isEmpty

        audioEngine.update(
            enabled: audioEnabled,
            paused: effectivelyPaused,
            volume: Float(audioVolume),
            windEnergy: physics.audioWindEnergy,
            rustleEnergy: physics.audioRustleEnergy,
            scene: selectedScene
        )

        let newCPUPercent = Int(round(physics.smoothedCPULoad * 100.0))
        if cpuPercent != newCPUPercent {
            cpuPercent = newCPUPercent
        }

        if effectivelyPaused {
            if !isCurrentlyPaused {
                isCurrentlyPaused = true
            }
            let reason = layers.isEmpty ? "No Active Surface" : (power.pauseReason ?? "Paused")
            if statusSummary != reason {
                statusSummary = reason
            }
            if wantsFrames, bridge.needsKeyframe, !powerCoordinator.isDisplayAsleep,
               let primaryLayer = windowManager.primaryDesktopLayer {
                let lighting = lightingRig.evaluate(preset: lightingPreset, dt: dt)
                renderer.renderToDrawable(
                    layer: primaryLayer,
                    sceneKind: selectedScene,
                    elapsedTime: elapsed,
                    dt: dt,
                    physics: physics,
                    lighting: lighting,
                    apertureScale: Float(bokehDepth),
                    cursorScale: Float(cursorReactivity),
                    windScale: Float(windReactivity),
                    broadcast: bridge
                )
            }
            scheduleRenderLoop(fps: 2)
            return
        }

        if isCurrentlyPaused {
            isCurrentlyPaused = false
        }

        scheduleRenderLoop(fps: power.targetFPS)
        if now - prevSelfSampleWall >= 1.0 {
            var ru = rusage()
            if getrusage(RUSAGE_SELF, &ru) == 0 {
                let cpuSec = Double(ru.ru_utime.tv_sec) + Double(ru.ru_utime.tv_usec) * 1e-6
                           + Double(ru.ru_stime.tv_sec) + Double(ru.ru_stime.tv_usec) * 1e-6
                if prevSelfSampleWall > 0 {
                    let wallDelta = max(now - prevSelfSampleWall, 0.1)
                    cachedSelfCPUPercent = max(0.1, ((cpuSec - prevSelfCPUTime) / wallDelta) * 100.0)
                }
                prevSelfCPUTime = cpuSec
                prevSelfSampleWall = now
            }
        }
        let summary = String(format: "%d FPS · %.1f%% CPU", power.targetFPS, cachedSelfCPUPercent)
        if statusSummary != summary {
            statusSummary = summary
        }

        let lighting = lightingRig.evaluate(preset: lightingPreset, dt: dt)

        for layer in layers {
            renderer.renderToDrawable(
                layer: layer,
                sceneKind: selectedScene,
                elapsedTime: elapsed,
                dt: dt,
                physics: physics,
                lighting: lighting,
                apertureScale: Float(bokehDepth),
                cursorScale: Float(cursorReactivity),
                windScale: Float(windReactivity),
                broadcast: wantsFrames && layer === windowManager.primaryDesktopLayer ? bridge : nil
            )
        }
    }
}
