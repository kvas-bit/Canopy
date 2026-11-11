# Sunrise — Canopy

**Matrix name:** Sunrise | Sati's living sky & world rendered behind the Matrix  
**Stack:** Swift 6 + Metal (MSL) + AppKit/SwiftUI + AVAudioEngine  
**Owner:** Kavi Vasudeo

## What it does
Lightweight native macOS live-rendered desktop wallpaper engine (`kCGDesktopWindowLevel`) driven by subliminal CPU/network telemetry and cursor breeze wakes. Includes 5 procedural Metal scenes (Grass-Swept Meadow, Wild Meadow, Misty Moss & Fern, Forest Stream, Coastal Dunes), shared hardware-depth `.min` 4x MSAA + circular Bokeh DoF, solar/mood lighting, and optional procedural wind synthesis.

## Build & Verify
```bash
swift build
swift test
make              # Compiles .metal -> default.metallib and builds Canopy.app
make snapshot     # Renders headless GPU PNG snapshots to .build/snapshots
```

## Key paths
- `Sources/CanopyKit/Engine/` — Telemetry, organic physics bus, lighting rig, occlusion/power coordinator, Metal HDR + Bokeh renderer
- `Sources/CanopyKit/Scenes/` — Modular `MetalScene` implementations
- `Sources/CanopyKit/Shaders/` — Metal Shading Language (`.metal`) GPU shaders + `ShaderShared.h`
- `Sources/CanopyKit/Audio/` — Real-time procedural wind/nature `AVAudioSourceNode` synth
- `Sources/CanopyKit/App/` — Desktop window manager, preview window, menu bar popover

## Rules
- Never block main thread; halt rendering (0% GPU) when desktop is occluded or asleep
- Zero TCC invasive permissions (`NSEvent.mouseLocation` + Mach `host_statistics64` only)
- Always pass `swift build` and `swift test` before structural changes
