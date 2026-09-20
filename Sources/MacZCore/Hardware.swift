import Darwin
import Foundation
import Metal

public enum Format {
    public static func bytes(_ value: UInt64) -> String {
        let units = ["B", "KiB", "MiB", "GiB", "TiB"]
        var amount = Double(value)
        var index = 0
        while amount >= 1024 && index < units.count - 1 {
            amount /= 1024
            index += 1
        }
        return String(format: amount.rounded() == amount ? "%.0f %@" : "%.1f %@", amount, units[index])
    }

    public static func uptime(_ seconds: TimeInterval) -> String {
        let minutes = max(0, Int(seconds)) / 60
        let days = minutes / 1440
        let hours = (minutes % 1440) / 60
        return days > 0 ? "\(days)d \(hours)h \(minutes % 60)m" : "\(hours)h \(minutes % 60)m"
    }
}

public enum Sysctl {
    public static func string(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var data = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &data, &size, nil, 0) == 0 else { return nil }
        return data.withUnsafeBufferPointer { String(cString: $0.baseAddress!) }
    }

    public static func integer(_ name: String) -> UInt64? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0 else { return nil }
        if size == MemoryLayout<UInt32>.size {
            var value: UInt32 = 0
            guard sysctlbyname(name, &value, &size, nil, 0) == 0 else { return nil }
            return UInt64(value)
        }
        guard size == MemoryLayout<UInt64>.size else { return nil }
        var value: UInt64 = 0
        guard sysctlbyname(name, &value, &size, nil, 0) == 0 else { return nil }
        return value
    }
}

public struct Spec: Identifiable, Sendable {
    public var id: String { label }
    public let label: String
    public let value: String
    public init(_ label: String, _ value: String) {
        self.label = label
        self.value = value
    }
}

public struct GPU: Identifiable, Sendable {
    public let id: Int
    public let name: String
    public let unified: Bool
    public let recommendedMemory: UInt64
    public let lowPower: Bool
    public let removable: Bool
    public let maxThreads: Int

    public var specs: [Spec] {
        [Spec("Memory", unified ? "Unified with CPU" : "Dedicated"),
         Spec("Recommended working set", Format.bytes(recommendedMemory)),
         Spec("Low-power device", lowPower ? "Yes" : "No"),
         Spec("Removable", removable ? "Yes" : "No"),
         Spec("Max threads per group", String(maxThreads))]
    }
}

public struct Hardware: Sendable {
    public let chip: String
    public let model: String
    public let architecture: String
    public let physicalCores: UInt64
    public let logicalCores: UInt64
    public let memory: UInt64
    public let cpu: [Spec]
    public let caches: [Spec]
    public let gpus: [GPU]
    public let os: String
    public let build: String
    public let kernel: String
    public let translated: Bool

    public static func read() -> Hardware {
        read(integer: Sysctl.integer, string: Sysctl.string)
    }

    static func read(integer: (String) -> UInt64?, string: (String) -> String?) -> Hardware {
        let arm = integer("hw.optional.arm64") == 1
        // Available counts can shrink with power management; these are hardware specifications.
        let physical = integer("hw.physicalcpu_max") ?? integer("hw.physicalcpu") ?? 0
        let logical = integer("hw.logicalcpu_max") ?? integer("hw.logicalcpu") ?? 0
        let chip = string("machdep.cpu.brand_string") ?? "Unknown processor"
        var cpu = [Spec("Processor", chip), Spec("Architecture", arm ? "Apple silicon · ARM64" : "Intel · x86_64"),
                   Spec("Physical cores", String(physical)), Spec("Logical processors", String(logical))]
        var caches: [Spec] = []
        let levels = min(integer("hw.nperflevels") ?? 0, 8)
        for index in 0..<levels {
            let prefix = "hw.perflevel\(index)"
            let name = string("\(prefix).name") ?? "Core group \(index + 1)"
            if let count = integer("\(prefix).physicalcpumax") ?? integer("\(prefix).physicalcpu") {
                cpu.append(Spec("\(name) cores", String(count)))
            }
            for (key, label) in [("l1icachesize", "L1 instruction"), ("l1dcachesize", "L1 data"), ("l2cachesize", "L2 cache")] {
                if let bytes = integer("\(prefix).\(key)"), bytes > 0 {
                    caches.append(Spec("\(name) · \(label)", Format.bytes(bytes)))
                }
            }
        }
        if caches.isEmpty {
            for (key, label) in [("hw.l1icachesize", "L1 instruction"), ("hw.l1dcachesize", "L1 data"), ("hw.l2cachesize", "L2 cache"), ("hw.l3cachesize", "L3 cache")] {
                if let bytes = integer(key), bytes > 0 { caches.append(Spec(label, Format.bytes(bytes))) }
            }
        }
        // Rosetta supplies a synthetic x86 frequency; it is not an Apple silicon clock.
        if !arm, let frequency = integer("hw.cpufrequency"), frequency > 0 {
            cpu.append(Spec("Reported frequency", String(format: "%.2f GHz", Double(frequency) / 1e9)))
        }
        let gpus = MTLCopyAllDevices().enumerated().map { index, device in
            GPU(id: index, name: device.name, unified: device.hasUnifiedMemory,
                recommendedMemory: device.recommendedMaxWorkingSetSize,
                lowPower: device.isLowPower, removable: device.isRemovable,
                maxThreads: device.maxThreadsPerThreadgroup.width)
        }
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return Hardware(chip: chip, model: string("hw.model") ?? "Unknown Mac",
                        architecture: arm ? "ARM64" : "x86_64", physicalCores: physical, logicalCores: logical,
                        memory: ProcessInfo.processInfo.physicalMemory, cpu: cpu, caches: caches, gpus: gpus,
                        os: "macOS \(version.majorVersion).\(version.minorVersion).\(version.patchVersion)",
                        build: string("kern.osversion") ?? "Unavailable",
                        kernel: string("kern.osrelease") ?? "Unavailable",
                        translated: integer("sysctl.proc_translated") == 1)
    }

    public var system: [Spec] {
        [Spec("Model identifier", model), Spec("Operating system", os), Spec("Build", build),
         Spec("Kernel", "Darwin \(kernel)"), Spec("Architecture", architecture),
         Spec("App running under Rosetta", translated ? "Yes" : "No")]
    }

    // Deliberately export an allowlist. Never include hostnames, usernames, serials or UUIDs.
    public func report(metrics: Metrics?, paused: Bool = false) -> String {
        var sections = ["MacZ 0.1.0", "[System]\n" + lines(system), "[CPU]\n" + lines(cpu),
                        "[Caches]\n" + (caches.isEmpty ? "Unavailable" : lines(caches)),
                        "[Memory]\nInstalled: \(Format.bytes(memory))"]
        for gpu in gpus { sections.append("[Graphics: \(gpu.name)]\n" + lines(gpu.specs)) }
        if let metrics {
            var current: [Spec] = []
            if let cpu = metrics.cpu { current.append(Spec("CPU usage", String(format: "%.1f%%", cpu.total))) }
            if let memory = metrics.memory {
                current += [Spec("Memory used (estimate)", Format.bytes(memory.used)),
                            Spec("Wired", Format.bytes(memory.wired)), Spec("Compressed", Format.bytes(memory.compressed))]
            }
            if let swap = metrics.swapUsed { current.append(Spec("Swap used", Format.bytes(swap))) }
            current += [Spec("Uptime", Format.uptime(metrics.uptime)), Spec("Thermal state", metrics.thermal)]
            sections.append((paused ? "[Paused activity]\n" : "[Current activity]\n") + lines(current))
        }
        return sections.joined(separator: "\n\n") + "\n"
    }

    private func lines(_ specs: [Spec]) -> String {
        specs.map { "\($0.label): \($0.value)" }.joined(separator: "\n")
    }
}
