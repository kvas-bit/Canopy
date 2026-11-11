import AppKit
import SwiftUI

public struct MenuBarPopoverView: View {
    @ObservedObject var controller: CanopyController

    public init(controller: CanopyController) {
        self.controller = controller
    }

    private let columns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8)
    ]

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            headerSection
            Divider().opacity(0.45)
            sceneGridSection
            lightingSection
            Divider().opacity(0.45)
            slidersSection
            audioSection
            Divider().opacity(0.45)
            footerSection
        }
        .padding(14)
        .frame(width: 336)
    }

    private var headerSection: some View {
        HStack(spacing: 8) {
            Image(systemName: "leaf.circle.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.green)

            VStack(alignment: .leading, spacing: 1) {
                Text("Canopy")
                    .font(.system(size: 13.5, weight: .semibold))
                HStack(spacing: 5) {
                    Circle()
                        .fill(controller.isCurrentlyPaused ? Color.orange : Color.green)
                        .frame(width: 6, height: 6)
                    Text(controller.statusSummary)
                        .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Button {
                controller.userPaused.toggle()
            } label: {
                Image(systemName: controller.userPaused ? "play.fill" : "pause.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 26, height: 24)
            }
            .buttonStyle(.bordered)
            .help(controller.userPaused ? "Resume Live Wallpaper" : "Pause Live Wallpaper")
        }
    }

    private var sceneGridSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("SCENE")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)

            LazyVGrid(columns: columns, spacing: 7) {
                ForEach(SceneKind.allCases) { scene in
                    let selected = controller.selectedScene == scene
                    Button {
                        controller.selectedScene = scene
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 5) {
                                Image(systemName: scene.symbolName)
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(selected ? Color.green : Color.secondary)
                                Text(scene.title)
                                    .font(.system(size: 11.5, weight: .semibold))
                                    .lineLimit(1)
                            }
                            Text(scene.subtitle)
                                .font(.system(size: 9.5))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 7)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(selected ? Color.green.opacity(0.16) : Color.primary.opacity(0.05))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(selected ? Color.green.opacity(0.65) : Color.primary.opacity(0.08), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var lightingSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("LIGHTING")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)

            HStack(spacing: 5) {
                ForEach(LightingPreset.allCases) { preset in
                    let active = controller.lightingPreset == preset
                    Button {
                        controller.lightingPreset = preset
                    } label: {
                        VStack(spacing: 3) {
                            Image(systemName: preset.symbolName)
                                .font(.system(size: 11.5))
                            Text(preset.label)
                                .font(.system(size: 9.5, weight: .medium))
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(active ? Color.accentColor.opacity(0.20) : Color.primary.opacity(0.04))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .strokeBorder(active ? Color.accentColor.opacity(0.65) : Color.clear, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var slidersSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("ORGANIC REACTIVITY & OPTICS")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)

            compactSlider(
                title: "System Wind",
                valueText: "\(Int(round(controller.windReactivity * 100)))%",
                value: $controller.windReactivity,
                range: 0.0...2.0
            )
            compactSlider(
                title: "Cursor Breeze",
                valueText: "\(Int(round(controller.cursorReactivity * 100)))%",
                value: $controller.cursorReactivity,
                range: 0.0...2.0
            )
            compactSlider(
                title: "Bokeh Depth",
                valueText: "\(Int(round(controller.bokehDepth * 100)))%",
                value: $controller.bokehDepth,
                range: 0.0...1.6
            )
        }
    }

    private func compactSlider(
        title: String,
        valueText: String,
        value: Binding<Double>,
        range: ClosedRange<Double>
    ) -> some View {
        VStack(spacing: 2) {
            HStack {
                Text(title)
                    .font(.system(size: 11))
                Spacer()
                Text(valueText)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            Slider(value: value, in: range)
                .controlSize(.small)
        }
    }

    private var audioSection: some View {
        VStack(alignment: .leading, spacing: 5) {
            Toggle(isOn: $controller.audioEnabled) {
                HStack(spacing: 6) {
                    Image(systemName: controller.audioEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(controller.audioEnabled ? .green : .secondary)
                    Text("Procedural Wind Audio")
                        .font(.system(size: 11.5, weight: .medium))
                }
            }
            .toggleStyle(.switch)
            .controlSize(.small)

            if controller.audioEnabled {
                Slider(value: $controller.audioVolume, in: 0.05...1.0)
                    .controlSize(.small)
            }
        }
    }

    private var footerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Toggle("Desktop", isOn: $controller.desktopWallpaperEnabled)
                    .toggleStyle(.checkbox)
                    .font(.system(size: 11))

                Toggle("Auto-Pause Covered", isOn: $controller.pauseWhenOccluded)
                    .toggleStyle(.checkbox)
                    .font(.system(size: 11))
            }

            HStack(spacing: 8) {
                Picker("", selection: $controller.fpsMode) {
                    ForEach(FPSCapMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .labelsHidden()
                .controlSize(.small)
                .frame(width: 128)

                Button {
                    controller.togglePreview()
                } label: {
                    Text(controller.isPreviewOpen ? "Hide Preview" : "Preview Window")
                        .font(.system(size: 11, weight: .medium))
                }
                .controlSize(.small)

                Spacer()

                Button("Quit") {
                    controller.shutdown()
                    NSApp.terminate(nil)
                }
                .controlSize(.small)
            }
        }
    }
}
