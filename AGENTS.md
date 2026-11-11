# AGENTS.md — Sunrise (Canopy)

## Goal
Build and maintain Canopy: a lightweight, photorealistic live-rendered macOS desktop background engine in Swift + Metal with subliminal system/cursor reactivity, 4 modular nature scenes, lighting modes, procedural wind audio, and strict occlusion/battery guardrails.

## Context
- Stack: Swift Package (`CanopyKit` + `Canopy`), Metal Shading Language, AppKit (`kCGDesktopWindowLevel`), SwiftUI Menu Bar popover, `AVAudioEngine`
- Build: `swift build` or `make` (builds `Canopy.app` with precompiled `default.metallib`)
- Test: `swift test` and `make snapshot` (headless GPU snapshot verification)

## Constraints
- Pause rendering completely (0% GPU/CPU) when windows occlude >92% of desktop or display sleeps
- No Accessibility/Input Monitoring TCC prompts — global cursor coordinates via `NSEvent.mouseLocation` only
- All new scenes must conform to `MetalScene` and consume the shared `FrameUniforms` + `CursorImpulse` buffers and HDR Bokeh post-processing pass

## Done when
- [ ] `swift build` and `swift test` pass cleanly
- [ ] `make` produces `Canopy.app` with compiled `default.metallib`
- [ ] `make snapshot` renders verified HDR + Bokeh frames for all 5 scenes (Grass-Swept Meadow, Wild Meadow, Misty Moss & Fern, Forest Stream, Coastal Dunes)
- [ ] Menu bar popover switches scenes, lighting modes, sensitivity sliders, preview window, and wind audio smoothly
