import Darwin
import Foundation

public struct ChipTemperature: Sendable, Equatable {
    public let hottest: Double
    public let average: Double
}

/// Apple silicon die sensors, read through IOKit's private HID event system without privileges.
/// Symbols are resolved at runtime so a macOS release without them leaves the reading unavailable.
final class ChipTemperatureSensors: @unchecked Sendable {
    private typealias CreateClient = @convention(c) (CFAllocator?) -> Unmanaged<CFTypeRef>?
    private typealias SetMatching = @convention(c) (CFTypeRef, CFDictionary) -> Int32
    private typealias CopyServices = @convention(c) (CFTypeRef) -> Unmanaged<CFArray>?
    private typealias CopyProperty = @convention(c) (CFTypeRef, CFString) -> Unmanaged<CFTypeRef>?
    private typealias CopyEvent = @convention(c) (CFTypeRef, Int64, Int32, Int64) -> Unmanaged<CFTypeRef>?
    private typealias FloatValue = @convention(c) (CFTypeRef, Int32) -> Double

    private static let temperatureEvent: Int64 = 15
    private static let temperatureField = Int32(temperatureEvent << 16)
    // The kernel reports disconnected sensors with large negative sentinels.
    private static let plausible = 0.0...150.0

    private let copyEvent: CopyEvent
    private let floatValue: FloatValue
    private let client: CFTypeRef // Keeps the service handles alive.
    private let services: [CFTypeRef]
    private let queue = DispatchQueue(label: "MacZ.chip-temperature", qos: .utility)
    private let lock = NSLock()
    private var latest: ChipTemperature?
    private var refreshing = false

    init?() {
        guard let create: CreateClient = Self.symbol("IOHIDEventSystemClientCreate"),
              let setMatching: SetMatching = Self.symbol("IOHIDEventSystemClientSetMatching"),
              let copyServices: CopyServices = Self.symbol("IOHIDEventSystemClientCopyServices"),
              let copyProperty: CopyProperty = Self.symbol("IOHIDServiceClientCopyProperty"),
              let copyEvent: CopyEvent = Self.symbol("IOHIDServiceClientCopyEvent"),
              let floatValue: FloatValue = Self.symbol("IOHIDEventGetFloatValue"),
              let client = create(kCFAllocatorDefault)?.takeRetainedValue() else { return nil }
        _ = setMatching(client, ["PrimaryUsagePage": 0xff00, "PrimaryUsage": 5] as CFDictionary)
        guard let all = copyServices(client)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        services = all.filter { service in
            let name = copyProperty(service, "Product" as CFString)?.takeRetainedValue() as? String
            return name.map(Self.isDieSensor) ?? false
        }
        guard !services.isEmpty else { return nil }
        self.client = client
        self.copyEvent = copyEvent
        self.floatValue = floatValue
    }

    /// Returns the previous reading and starts the next one. Reading every sensor waits about 45 ms on
    /// the hardware, which would stall the caller's thread.
    func read() -> ChipTemperature? {
        lock.withLock {
            if !refreshing {
                refreshing = true
                queue.async { self.refresh() }
            }
            return latest
        }
    }

    func reset() { lock.withLock { latest = nil } }

    private func refresh() {
        let reading = Self.summary(services.compactMap { service in
            copyEvent(service, Self.temperatureEvent, 0, 0).map { floatValue($0.takeRetainedValue(), Self.temperatureField) }
        })
        lock.withLock {
            latest = reading
            refreshing = false
        }
    }

    static func isDieSensor(_ name: String) -> Bool { name.hasPrefix("PMU tdie") }

    static func summary(_ readings: [Double]) -> ChipTemperature? {
        let valid = readings.filter { $0.isFinite && plausible.contains($0) }
        guard let hottest = valid.max() else { return nil }
        return ChipTemperature(hottest: hottest, average: valid.reduce(0, +) / Double(valid.count))
    }

    private static func symbol<T>(_ name: String) -> T? {
        let defaultHandle = UnsafeMutableRawPointer(bitPattern: -2) // RTLD_DEFAULT
        return dlsym(defaultHandle, name).map { unsafeBitCast($0, to: T.self) }
    }
}
