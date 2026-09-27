import XCTest
@testable import MacZCore

final class MacZCoreTests: XCTestCase {
    func testHardwareUsesMaximumCoreCountsInReducedPowerMode() {
        let values: [String: UInt64] = [
            "hw.optional.arm64": 1, "hw.physicalcpu": 4, "hw.physicalcpu_max": 12,
            "hw.logicalcpu": 4, "hw.logicalcpu_max": 12, "hw.nperflevels": 1,
            "hw.perflevel0.physicalcpu": 2, "hw.perflevel0.physicalcpumax": 8
        ]
        let hardware = Hardware.read(integer: { values[$0] }, string: { _ in nil })
        XCTAssertEqual(hardware.physicalCores, 12)
        XCTAssertEqual(hardware.logicalCores, 12)
        XCTAssertEqual(hardware.cpu.first { $0.label == "Core group 1 cores" }?.value, "8")
    }

    func testHardwareFallsBackWhenMaximumCountsAreUnavailable() {
        let values: [String: UInt64] = ["hw.physicalcpu": 4, "hw.logicalcpu": 8]
        let hardware = Hardware.read(integer: { values[$0] }, string: { _ in nil })
        XCTAssertEqual(hardware.physicalCores, 4)
        XCTAssertEqual(hardware.logicalCores, 8)
    }

    func testGPUCountersHandleMissingAndInvalidReadings() {
        XCTAssertEqual(GPUUsage.percentage(from: ["Device Utilization %": 42.5]), 42.5)
        XCTAssertEqual(GPUUsage.percentage(from: ["GPU Activity(%)": 17]), 17)
        XCTAssertEqual(GPUUsage.percentage(from: ["Device Utilization %": 0, "GPU Activity(%)": 90]), 0)
        XCTAssertEqual(GPUUsage.percentage(from: ["Device Utilization %": 150]), 100)
        XCTAssertNil(GPUUsage.percentage(from: [:]))
        XCTAssertNil(GPUUsage.percentage(from: ["Renderer Utilization %": 30]))
        for invalid: Any in [-1, Double.nan, Double.infinity, true, "42"] {
            XCTAssertNil(GPUUsage.percentage(from: ["Device Utilization %": invalid]))
        }
        XCTAssertEqual(GPUUsage.percentage(from: ["Device Utilization %": -1, "GPU Activity(%)": 20]), 20)
    }

    func testChipTemperatureIgnoresInvalidReadingsAndOtherSensors() throws {
        let summary = try XCTUnwrap(ChipTemperatureSensors.summary([80, 70, -9201.1, .nan, .infinity, 900]))
        XCTAssertEqual(summary, ChipTemperature(hottest: 80, average: 75))
        XCTAssertNil(ChipTemperatureSensors.summary([]))
        XCTAssertNil(ChipTemperatureSensors.summary([-9201.1]))
        XCTAssertTrue(ChipTemperatureSensors.isDieSensor("PMU tdie12"))
        for other in ["PMU tdev1", "PMU tcal", "NAND CH0 temp", "gas gauge battery"] {
            XCTAssertFalse(ChipTemperatureSensors.isDieSensor(other))
        }
        XCTAssertEqual(Format.celsius(84.6), "85 °C")
    }

    func testDockHistoryRetainsOneMinuteAndMissingTimeSlots() {
        var history = DockHistory()
        for index in 0..<35 { history.append(cpu: Double(index), gpu: index == 34 ? nil : Double(index)) }
        XCTAssertEqual(history.samples.count, 30)
        XCTAssertEqual(history.samples.first?.cpu, 5)
        XCTAssertEqual(history.samples.last?.cpu, 34)
        XCTAssertNil(history.samples.last?.gpu)
        history.reset()
        XCTAssertTrue(history.samples.isEmpty)
        history.append(cpu: nil, gpu: 0)
        XCTAssertEqual(history.samples.count, 1)
        XCTAssertNil(history.samples[0].cpu)
        XCTAssertEqual(history.samples[0].gpu, 0)
    }

    func testCPUUsesDeltaAndIncludesNice() throws {
        let before = CPUTicks(user: 100, system: 50, idle: 200, nice: 10)
        let after = CPUTicks(user: 120, system: 60, idle: 265, nice: 15)
        let usage = try XCTUnwrap(after.usage(since: before))
        XCTAssertEqual(usage.user, 25, accuracy: 0.001)
        XCTAssertEqual(usage.system, 10, accuracy: 0.001)
        XCTAssertEqual(usage.total, 35, accuracy: 0.001)
        XCTAssertNil(before.usage(since: before))
    }

    func testCPUCounterWrap() throws {
        let before = CPUTicks(user: UInt32.max - 4, system: 0, idle: 0, nice: 0)
        let after = CPUTicks(user: 5, system: 0, idle: 10, nice: 0)
        XCTAssertEqual(try XCTUnwrap(after.usage(since: before)).total, 50, accuracy: 0.001)
    }

    func testMemorySubtractsReclaimableAndClamps() {
        let memory = MemoryUsage(active: 400, inactive: 200, wired: 100, compressed: 50, purgeable: 20, external: 180, total: 1000)
        XCTAssertEqual(memory.used, 550)
        XCTAssertEqual(memory.fraction, 0.55, accuracy: 0.001)
        XCTAssertEqual(MemoryUsage(active: 0, inactive: 0, wired: 0, compressed: 0, purgeable: 50, external: 50, total: 1000).used, 0)
        XCTAssertEqual(MemoryUsage(active: 2000, inactive: 0, wired: 0, compressed: 0, purgeable: 0, external: 0, total: 1000).used, 1000)
    }

    func testBinaryUnitsAndUptime() {
        XCTAssertEqual(Format.bytes(24 * 1024 * 1024 * 1024), "24 GiB")
        XCTAssertEqual(Format.bytes(1536), "1.5 KiB")
        XCTAssertEqual(Format.bytes(0), "0 B")
        XCTAssertEqual(Format.uptime(90061), "1d 1h 1m")
    }

    func testLiveReadersAndReportPrivacy() throws {
        let hardware = Hardware.read()
        XCTAssertGreaterThan(hardware.memory, 0)
        XCTAssertGreaterThan(hardware.physicalCores, 0)
        let sampler = Sampler()
        XCTAssertNil(sampler.sample().cpu)
        // The kernel's aggregate CPU counters can go several hundred milliseconds without advancing.
        var metrics = sampler.sample()
        for _ in 0..<40 where metrics.cpu == nil {
            Thread.sleep(forTimeInterval: 0.05)
            metrics = sampler.sample()
        }
        XCTAssertNotNil(metrics.cpu)
        if let gpu = metrics.gpu { XCTAssertTrue((0...100).contains(gpu)) }
        XCTAssertGreaterThan(try XCTUnwrap(metrics.memory).used, 0)
        let report = hardware.report(metrics: metrics)
        if hardware.architecture == "ARM64" {
            XCTAssertFalse(report.contains("Reported frequency"), "Apple silicon must not expose Rosetta's synthetic clock")
        }
        for forbidden in [NSUserName(), NSHomeDirectory(), ProcessInfo.processInfo.hostName] where !forbidden.isEmpty {
            XCTAssertFalse(report.contains(forbidden), "Report contains a private identifier")
        }
        XCTAssertFalse(report.lowercased().contains("serial"))
        XCTAssertFalse(report.lowercased().contains("uuid"))
        sampler.reset()
        XCTAssertNil(sampler.sample().cpu)
    }

    func testChipTemperatureArrivesOnALaterSample() throws {
        let sampler = Sampler()
        XCTAssertNil(sampler.sample().temperature, "The first sample only starts the background read")
        guard Hardware.read().architecture == "ARM64" else { return }
        var temperature: ChipTemperature?
        for _ in 0..<20 where temperature == nil {
            Thread.sleep(forTimeInterval: 0.1)
            temperature = sampler.sample().temperature
        }
        let reading = try XCTUnwrap(temperature, "Apple silicon die sensors are readable without privileges")
        XCTAssertTrue((0...150).contains(reading.hottest))
        XCTAssertLessThanOrEqual(reading.average, reading.hottest)
        sampler.reset()
        XCTAssertNil(sampler.sample().temperature)
    }
}
