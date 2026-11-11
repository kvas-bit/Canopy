import AppKit
import CanopyKit
import Foundation

let args = CommandLine.arguments
if let idx = args.firstIndex(of: "--snapshot"), idx + 1 < args.count {
    do {
        try CanopyCLI.runSnapshotBatch(outputDir: args[idx + 1])
        exit(0)
    } catch {
        fputs("Snapshot error: \(error)\n", stderr)
        exit(1)
    }
}

let app = NSApplication.shared
let delegate = MainActor.assumeIsolated { CanopyAppDelegate() }
app.delegate = delegate
app.run()
