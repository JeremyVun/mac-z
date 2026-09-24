import Combine
import AppKit
import XCTest
@testable import MacZ

final class SamplingTests: XCTestCase {
    @MainActor
    func testPausedReportDoesNotClaimReadingsAreCurrent() {
        _ = NSApplication.shared
        let model = AppModel()
        model.sample()
        model.paused = true
        var report = ""
        model.copyReport { report = $0; return true }
        XCTAssertTrue(report.contains("[Paused activity]"))
        XCTAssertFalse(report.contains("[Current activity]"))
    }

    @MainActor
    func testCopyReportOnlyConfirmsSuccessfulWrites() {
        _ = NSApplication.shared
        let model = AppModel()
        var report = ""
        model.copyReport { report = $0; return true }
        XCTAssertTrue(report.hasPrefix("MacZ 0.1.0\n"))
        XCTAssertTrue(model.copied)
        XCTAssertFalse(model.copyFailed)
        model.copyReport { _ in false }
        XCTAssertFalse(model.copied)
        XCTAssertTrue(model.copyFailed)
        model.copyReport { _ in true }
        XCTAssertTrue(model.copied)
        XCTAssertFalse(model.copyFailed)
    }

    @MainActor
    func testSamplingWithoutAWindowAndPauseResumeSleep() async throws {
        _ = NSApplication.shared
        let model = AppModel()
        defer {
            model.stopSampling()
            NSApp.dockTile.contentView = nil
            NSApp.dockTile.badgeLabel = nil
        }
        model.startSampling()
        XCTAssertNotNil(model.samplingActivity)
        XCTAssertNil(model.metrics?.cpu)
        XCTAssertNotNil(NSApp.dockTile.contentView)
        // No SwiftUI view or active scene exists in this test.
        try await Task.sleep(for: .milliseconds(2300))
        XCTAssertFalse(model.cpuHistory.isEmpty)
        XCTAssertNotNil(model.metrics?.cpu)

        model.paused = true
        XCTAssertNil(model.samplingActivity)
        let pausedUptime = model.metrics?.uptime
        XCTAssertEqual(NSApp.dockTile.badgeLabel, "Paused")
        try await Task.sleep(for: .milliseconds(2300))
        XCTAssertEqual(model.metrics?.uptime, pausedUptime)

        model.setSleeping(true)
        model.setSleeping(false)
        XCTAssertTrue(model.paused)
        XCTAssertEqual(model.metrics?.uptime, pausedUptime)
        model.paused = false
        XCTAssertNil(model.metrics?.cpu, "Resuming must reset the CPU baseline")
        XCTAssertEqual(model.cpuHistory.count, 1)
        XCTAssertNil(model.cpuHistory[0])
        XCTAssertNotNil(model.samplingActivity)
        XCTAssertNil(NSApp.dockTile.badgeLabel)
        model.setSleeping(true)
        XCTAssertNil(model.samplingActivity)
        let sleepUptime = model.metrics?.uptime
        try await Task.sleep(for: .milliseconds(2300))
        XCTAssertEqual(model.metrics?.uptime, sleepUptime)
        model.setSleeping(false)
        XCTAssertNil(model.metrics?.cpu)
        XCTAssertEqual(model.cpuHistory.count, 1)
        XCTAssertNil(model.cpuHistory[0])
        XCTAssertNotNil(model.samplingActivity)
        XCTAssertGreaterThan(try XCTUnwrap(model.metrics?.uptime), try XCTUnwrap(sleepUptime))
    }

    @MainActor
    func testDelayedSamplingDiscardsStaleHistoryAndCPUBaseline() {
        _ = NSApplication.shared
        let model = AppModel()
        let start = ContinuousClock.now
        model.sample(at: start)
        model.sample(at: start.advanced(by: .seconds(2)))
        XCTAssertEqual(model.cpuHistory.count, 2)
        XCTAssertEqual(model.memoryHistory.count, 2)
        XCTAssertEqual(model.dockHistory.samples.count, 2)

        model.sample(at: start.advanced(by: .seconds(20)))
        XCTAssertNil(model.metrics?.cpu)
        XCTAssertEqual(model.cpuHistory.count, 1)
        XCTAssertNil(model.cpuHistory[0])
        XCTAssertEqual(model.memoryHistory.count, 1)
        XCTAssertEqual(model.dockHistory.samples.count, 1)
        XCTAssertNil(model.dockHistory.samples[0].cpu)
    }

    @MainActor
    func testHiddenWindowSkipsRefreshesButKeepsSampling() {
        _ = NSApplication.shared
        let model = AppModel()
        var refreshes = 0
        let subscription = model.objectWillChange.sink { refreshes += 1 }
        defer { subscription.cancel() }
        let start = ContinuousClock.now
        model.windowVisible = false
        model.sample(at: start)
        model.sample(at: start.advanced(by: .seconds(2)))
        XCTAssertEqual(refreshes, 0)
        XCTAssertEqual(model.cpuHistory.count, 2)
        XCTAssertEqual(model.dockHistory.samples.count, 2)

        model.windowVisible = true
        XCTAssertEqual(refreshes, 1)
        model.sample(at: start.advanced(by: .seconds(4)))
        XCTAssertGreaterThan(refreshes, 1)
    }

    @MainActor
    func testHistoriesRemainAlignedAndBounded() {
        _ = NSApplication.shared
        let model = AppModel()
        let start = ContinuousClock.now
        for index in 0..<65 {
            model.sample(at: start.advanced(by: .seconds(index * 2)))
        }
        XCTAssertEqual(model.cpuHistory.count, 60)
        XCTAssertEqual(model.memoryHistory.count, 60)
        XCTAssertEqual(model.dockHistory.samples.count, 30)
    }
}
