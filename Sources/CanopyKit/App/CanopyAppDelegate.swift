import AppKit
import Foundation
import SwiftUI

@MainActor
public final class CanopyAppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private let popover = NSPopover()
    private var controller: CanopyController?

    public override init() {
        super.init()
    }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        do {
            let ctrl = try CanopyController()
            self.controller = ctrl
            ctrl.start()

            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            if let button = item.button {
                let img = NSImage(systemSymbolName: "leaf.fill", accessibilityDescription: "Canopy")
                img?.isTemplate = true
                button.image = img
                button.action = #selector(togglePopover(_:))
                button.target = self
            }
            self.statusItem = item

            popover.contentSize = NSSize(width: 344, height: 505)
            popover.behavior = .transient
            popover.animates = true
            popover.contentViewController = NSHostingController(rootView: MenuBarPopoverView(controller: ctrl))

            if CommandLine.arguments.contains("--preview") {
                ctrl.togglePreview()
            }
        } catch {
            fputs("Canopy failed to initialize Metal engine: \(error)\n", stderr)
            NSApp.terminate(nil)
        }
    }

    public func applicationWillTerminate(_ notification: Notification) {
        controller?.shutdown()
    }

    @objc private func togglePopover(_ sender: AnyObject?) {
        guard let button = statusItem?.button else { return }
        if popover.isShown {
            popover.performClose(sender)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }
}

public enum CanopyCLI {
    public static func runSnapshotBatch(outputDir: String) throws {
        let outFolder = URL(fileURLWithPath: outputDir)
        try FileManager.default.createDirectory(at: outFolder, withIntermediateDirectories: true)

        let renderer = try CanopyController.makeDefaultRenderer()
        let jobs: [(String, SceneKind, LightingPreset, Float)] = [
            ("meadow_lush.png",      .wildflowerMeadow, .lightLush,  0.28),
            ("meadow_golden.png",    .wildflowerMeadow, .goldenHour, 0.55),
            ("meadow_dark.png",      .wildflowerMeadow, .darkMoody,  0.18),
            ("wild_meadow_lush.png", .wildMeadow,       .lightLush,  0.28),
            ("moss_lush.png",        .mistyMoss,        .lightLush,  0.25),
            ("moss_dark.png",        .mistyMoss,        .darkMoody,  0.20),
            ("stream_lush.png",      .forestStream,     .lightLush,  0.35),
            ("dunes_golden.png",     .coastalDunes,     .goldenHour, 0.45)
        ]

        for (filename, scene, preset, cpu) in jobs {
            let fileURL = outFolder.appendingPathComponent(filename)
            try SnapshotExporter.renderSnapshotPNG(
                renderer: renderer,
                scene: scene,
                lightingPreset: preset,
                width: 1600,
                height: 1000,
                elapsedTime: 16.2,
                cpuLoad: cpu,
                outputURL: fileURL
            )
            print("Rendered \(fileURL.path)")
        }
    }
}
