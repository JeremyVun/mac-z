import Foundation
import IOKit

public enum GPUUsage {
    // Driver-provided counters are not available on every Mac or macOS release.
    // Read only the performance property, not device identifiers or the registry tree.
    public static func read() -> Double? {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &iterator) == KERN_SUCCESS else {
            return nil
        }
        defer { IOObjectRelease(iterator) }
        var busiest: Double?
        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            guard let property = IORegistryEntryCreateCFProperty(service, "PerformanceStatistics" as CFString, kCFAllocatorDefault, 0),
                  let statistics = property.takeRetainedValue() as? [String: Any],
                  let usage = percentage(from: statistics) else { continue }
            busiest = max(busiest ?? 0, usage)
        }
        return busiest
    }

    static func percentage(from statistics: [String: Any]) -> Double? {
        for key in ["Device Utilization %", "GPU Activity(%)"] {
            guard let number = statistics[key] as? NSNumber,
                  CFGetTypeID(number) != CFBooleanGetTypeID() else { continue }
            let value = number.doubleValue
            guard value.isFinite, value >= 0 else { continue }
            return min(100, value)
        }
        return nil
    }
}

public struct ActivitySample: Sendable {
    public let cpu: Double?
    public let gpu: Double?
}

/// One minute of aligned, two-second readings. Missing values occupy a time slot.
public struct DockHistory: Sendable {
    public static let capacity = 30
    public private(set) var samples: [ActivitySample] = []

    public init() {}

    public mutating func append(cpu: Double?, gpu: Double?) {
        samples.append(ActivitySample(cpu: cpu, gpu: gpu))
        if samples.count > Self.capacity { samples.removeFirst(samples.count - Self.capacity) }
    }

    public mutating func reset() { samples.removeAll(keepingCapacity: true) }
}
