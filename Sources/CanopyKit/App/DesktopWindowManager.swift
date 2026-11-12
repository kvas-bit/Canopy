import AppKit
import Metal
import QuartzCore

public final class MetalSurfaceView: NSView {
    public let metalLayer: CAMetalLayer
    public var allowsReadback: Bool = false {
        didSet {
            if allowsReadback != oldValue {
                metalLayer.framebufferOnly = !allowsReadback
            }
        }
    }
    public var renderScale: CGFloat = 0.68 {
        didSet { updateDrawableSize() }
    }

    public init(frame frameRect: NSRect, device: MTLDevice) {
        self.metalLayer = CAMetalLayer()
        super.init(frame: frameRect)
        wantsLayer = true
        layerContentsRedrawPolicy = .never

        metalLayer.device = device
        metalLayer.pixelFormat = .bgra8Unorm
        metalLayer.framebufferOnly = true
        metalLayer.isOpaque = true
        metalLayer.displaySyncEnabled = true
        metalLayer.maximumDrawableCount = 3
        self.layer = metalLayer
        updateDrawableSize()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func makeBackingLayer() -> CALayer {
        metalLayer
    }

    public override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        updateDrawableSize()
    }

    public override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        updateDrawableSize()
    }

    public func updateDrawableSize() {
        let backing = min(window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2.0, 2.0)
        let effScale = backing * renderScale
        let w = max(CGFloat(16), round(bounds.width * effScale))
        let h = max(CGFloat(16), round(bounds.height * effScale))
        if metalLayer.drawableSize.width != w || metalLayer.drawableSize.height != h {
            metalLayer.drawableSize = CGSize(width: w, height: h)
        }
    }
}

@MainActor
public final class DesktopWindowManager: NSObject, NSWindowDelegate {
    private let device: MTLDevice
    private var desktopWindows: [NSWindow] = []
    private var desktopViews: [MetalSurfaceView] = []

    private var previewWindow: NSWindow?
    private var previewView: MetalSurfaceView?
    public var onPreviewVisibilityChanged: ((Bool) -> Void)?

    public private(set) var isDesktopEnabled: Bool = true

    public var isPreviewVisible: Bool {
        previewWindow?.isVisible ?? false
    }

    public var primaryDesktopLayer: CAMetalLayer? {
        desktopViews.first?.metalLayer
    }

    public func setPrimaryDesktopReadback(_ on: Bool) {
        desktopViews.first?.allowsReadback = on
    }

    public var previewScreenFrame: CGRect? {
        guard let win = previewWindow, win.isVisible, let content = win.contentView else { return nil }
        return win.convertToScreen(content.frame)
    }

    public init(device: MTLDevice) {
        self.device = device
        super.init()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screensDidChange),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    public func setDesktopEnabled(_ enabled: Bool) {
        isDesktopEnabled = enabled
        if enabled {
            rebuildDesktopWindows()
        } else {
            for win in desktopWindows {
                win.orderOut(nil)
            }
            desktopWindows.removeAll()
            desktopViews.removeAll()
        }
    }

    public func rebuildDesktopWindows() {
        for win in desktopWindows {
            win.orderOut(nil)
        }
        desktopWindows.removeAll()
        desktopViews.removeAll()

        guard isDesktopEnabled else { return }

        let desktopLevel = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)))

        for screen in NSScreen.screens {
            let frame = screen.frame
            let win = NSWindow(
                contentRect: frame,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            win.level = desktopLevel
            win.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenNone]
            win.ignoresMouseEvents = true
            win.isOpaque = true
            win.hasShadow = false
            win.backgroundColor = .black
            win.isReleasedWhenClosed = false

            let surface = MetalSurfaceView(frame: NSRect(origin: .zero, size: frame.size), device: device)
            surface.autoresizingMask = [.width, .height]
            win.contentView = surface
            surface.updateDrawableSize()
            win.orderFrontRegardless()

            desktopWindows.append(win)
            desktopViews.append(surface)
        }
    }

    public func togglePreviewWindow() {
        if let existing = previewWindow, existing.isVisible {
            existing.orderOut(nil)
            onPreviewVisibilityChanged?(false)
            return
        }
        showPreviewWindow()
    }

    public func showPreviewWindow() {
        if previewWindow == nil {
            let rect = NSRect(x: 0, y: 0, width: 980, height: 610)
            let win = NSWindow(
                contentRect: rect,
                styleMask: [.titled, .closable, .resizable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            win.title = "Canopy — Live Scene Preview"
            win.appearance = NSAppearance(named: .darkAqua)
            win.backgroundColor = .black
            win.minSize = NSSize(width: 520, height: 320)
            win.isReleasedWhenClosed = false
            win.delegate = self
            win.center()

            let view = MetalSurfaceView(frame: rect, device: device)
            view.renderScale = 0.80
            view.autoresizingMask = [.width, .height]
            win.contentView = view
            view.updateDrawableSize()

            self.previewWindow = win
            self.previewView = view
        }

        previewWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        onPreviewVisibilityChanged?(true)
    }

    public func windowWillClose(_ notification: Notification) {
        if (notification.object as? NSWindow) === previewWindow {
            onPreviewVisibilityChanged?(false)
        }
    }

    public func activeTargetLayers(skipDesktop: Bool = false) -> [CAMetalLayer] {
        var layers: [CAMetalLayer] = []
        if isDesktopEnabled && !skipDesktop {
            for v in desktopViews {
                layers.append(v.metalLayer)
            }
        }
        if let pv = previewView, previewWindow?.isVisible == true {
            layers.append(pv.metalLayer)
        }
        return layers
    }

    @objc private func screensDidChange() {
        if isDesktopEnabled {
            rebuildDesktopWindows()
        }
    }
}
