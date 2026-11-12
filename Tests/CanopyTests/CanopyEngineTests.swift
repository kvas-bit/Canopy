import XCTest
import simd
@testable import CanopyKit

final class CanopyEngineTests: XCTestCase {
    func testGPUUniformStructAlignmentMatchesMetal() {
        XCTAssertEqual(MemoryLayout<CursorImpulse>.size, 32)
        XCTAssertEqual(MemoryLayout<CursorImpulse>.stride, 32)
        XCTAssertEqual(MemoryLayout<FrameUniforms>.size, 368)
        XCTAssertEqual(MemoryLayout<FrameUniforms>.stride, 368)
    }

    func testOrganicPhysicsBusSubliminalSmoothingAndImpulses() {
        let bus = OrganicPhysicsBus()
        let idleSnap = TelemetrySnapshot(cpuUsage: 0.04, networkActivity: 0.0, cursorUV: SIMD2<Float>(0.2, 0.3), cursorOnDesktopScreen: true)
        let state0 = bus.step(dt: 0.033, elapsedTime: 1.0, telemetry: idleSnap, windReactivityScale: 1.0, cursorReactivityScale: 1.0)

        let spikeSnap = TelemetrySnapshot(cpuUsage: 0.95, networkActivity: 0.8, cursorUV: SIMD2<Float>(0.32, 0.38), cursorOnDesktopScreen: true)
        let state1 = bus.step(dt: 0.033, elapsedTime: 1.033, telemetry: spikeSnap, windReactivityScale: 1.0, cursorReactivityScale: 1.0)

        XCTAssertGreaterThan(state1.smoothedCPULoad, state0.smoothedCPULoad)
        XCTAssertLessThan(state1.smoothedCPULoad, 0.25, "CPU spikes should smooth subliminally over several seconds, not jump instantaneously")

        let activeImpulses = state1.impulses.filter { $0.velAndStrength.z > 0.001 }
        XCTAssertFalse(activeImpulses.isEmpty, "Moving cursor across desktop should spawn a breeze impulse")
    }

    func testSolarCycleTransitionsSmoothly() {
        let midnight = LightingRig.solarState(forDecimalHour: 1.0)
        let noon = LightingRig.solarState(forDecimalHour: 12.5)
        let sunset = LightingRig.solarState(forDecimalHour: 18.2)

        XCTAssertLessThan(midnight.solarWarmth, 0.2)
        XCTAssertGreaterThan(noon.solarWarmth, 0.8)
        XCTAssertGreaterThan(sunset.sunColor.x, sunset.sunColor.z)
    }

    func testSolarCalculatorTracksRealSunriseSunset() {
        // Boston, MA on Nov 12 2026 (EST, post-DST): real sunrise ≈ 6:30 AM,
        // sunset ≈ 4:22 PM, solar-noon elevation ≈ 30°.
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/New_York")!
        let lat = 42.36, lon = -71.06
        func boston(_ month: Int, _ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
            cal.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour, minute: minute))!
        }

        let day = boston(11, 12, 12)
        let noonElev = SolarCalculator.solarElevation(at: day, latitude: lat, longitude: lon)
        XCTAssertTrue((24.0...33.0).contains(noonElev), "Boston winter-noon sun should sit near 30°, got \(noonElev)")

        // Auto Solar must already be dark-ish at 5 PM in November — the old
        // clock-hour table kept it golden until 7 PM.
        let dusk = LightingRig.solarState(for: boston(11, 12, 17), latitude: lat, longitude: lon)
        XCTAssertLessThan(dusk.solarWarmth, 0.35)
        XCTAssertLessThan(dusk.sunIntensity, 1.8)
        let midday = LightingRig.solarState(for: day, latitude: lat, longitude: lon)
        XCTAssertGreaterThan(midday.solarWarmth, 0.8)

        // June 20 at 6 AM EDT: sun is up (~5:07 AM sunrise) — must not read as night.
        let summerDawnElev = SolarCalculator.solarElevation(at: boston(6, 20, 6), latitude: lat, longitude: lon)
        XCTAssertGreaterThan(summerDawnElev, 4.0)

        // Sunrise/sunset checker vs. real almanac values (±15 min).
        let (rise, set) = SolarCalculator.sunriseSunset(
            on: day, latitude: lat, longitude: lon,
            timeZone: TimeZone(identifier: "America/New_York")!
        )
        let dayStart = cal.startOfDay(for: day)
        let riseMin = (rise?.timeIntervalSince(dayStart) ?? -1) / 60.0
        let setMin = (set?.timeIntervalSince(dayStart) ?? -1) / 60.0
        XCTAssertTrue((370.0...415.0).contains(riseMin), "Computed sunrise should land ~6:30 AM, got \(riseMin) min")
        XCTAssertTrue((955.0...1000.0).contains(setMin), "Computed sunset should land ~4:22 PM, got \(setMin) min")
    }

    func testWindAdvectionNeverAcceleratesOverLongUptimeAtIdleCPU() {
        let bus = OrganicPhysicsBus()
        let idleSnap = TelemetrySnapshot(cpuUsage: 0.04, networkActivity: 0.0, cursorUV: SIMD2<Float>(0.5, 0.5), cursorOnDesktopScreen: false)

        let dt: Float = 1.0 / 30.0
        var t: Float = 0.0
        var prevOffset: SIMD2<Float> = .zero

        // Simulate 15 minutes (900 seconds = 27,000 frames) at 96% idle CPU
        for stepIdx in 0..<27_000 {
            t += dt
            let state = bus.step(dt: dt, elapsedTime: t, telemetry: idleSnap, windReactivityScale: 1.0, cursorReactivityScale: 1.0)
            if stepIdx > 0 {
                let effectiveSpeed = simd_length(state.windOffset - prevOffset) / dt
                XCTAssertLessThan(effectiveSpeed, 0.28, "Idle wind advection must stay calm (<0.28/s) even after long uptime")
            }
            prevOffset = state.windOffset
        }
    }

    func testMetalShadersCompileAndAllFourScenesRender() throws {
        let renderer = try CanopyController.makeDefaultRenderer()
        for kind in SceneKind.allCases {
            XCTAssertNotNil(renderer.scene(for: kind), "Missing scene \(kind)")
        }

        let tmpURL = FileManager.default.temporaryDirectory.appendingPathComponent("canopy_test_\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: tmpURL) }

        try SnapshotExporter.renderSnapshotPNG(
            renderer: renderer,
            scene: .wildflowerMeadow,
            lightingPreset: .lightLush,
            width: 320,
            height: 200,
            outputURL: tmpURL
        )
        let attrs = try FileManager.default.attributesOfItem(atPath: tmpURL.path)
        let size = (attrs[.size] as? NSNumber)?.intValue ?? 0
        XCTAssertGreaterThan(size, 5_000)
    }
}
