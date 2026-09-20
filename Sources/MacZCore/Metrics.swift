import Darwin
import Foundation

public struct CPUTicks: Sendable {
    public let user: UInt32
    public let system: UInt32
    public let idle: UInt32
    public let nice: UInt32

    public init(user: UInt32, system: UInt32, idle: UInt32, nice: UInt32) {
        self.user = user; self.system = system; self.idle = idle; self.nice = nice
    }

    public func usage(since previous: CPUTicks) -> CPUUsage? {
        // Kernel tick counters wrap; subtract before widening.
        let userDelta = Double(user &- previous.user) + Double(nice &- previous.nice)
        let systemDelta = Double(system &- previous.system)
        let total = userDelta + systemDelta + Double(idle &- previous.idle)
        guard total > 0 else { return nil }
        return CPUUsage(user: userDelta / total * 100, system: systemDelta / total * 100)
    }
}

public struct CPUUsage: Sendable {
    public let user: Double
    public let system: Double
    public var total: Double { min(100, user + system) }
}

public struct MemoryUsage: Sendable {
    public let used: UInt64
    public let wired: UInt64
    public let compressed: UInt64
    public let total: UInt64
    public var fraction: Double { total > 0 ? min(1, Double(used) / Double(total)) : 0 }

    public init(active: UInt64, inactive: UInt64, wired: UInt64, compressed: UInt64, purgeable: UInt64, external: UInt64, total: UInt64) {
        let occupied = active + inactive + wired + compressed
        let reclaimable = purgeable + external
        used = min(total, occupied > reclaimable ? occupied - reclaimable : 0)
        self.wired = wired
        self.compressed = compressed
        self.total = total
    }
}

public struct Metrics: Sendable {
    public let cpu: CPUUsage?
    public let gpu: Double?
    public let memory: MemoryUsage?
    public let swapUsed: UInt64?
    public let uptime: TimeInterval
    public let thermal: String
}

public final class Sampler {
    private var previous: CPUTicks?
    private let host: host_t

    public init() { host = mach_host_self() }
    deinit { mach_port_deallocate(mach_task_self_, host) }

    public func sample() -> Metrics {
        let ticks = cpuTicks()
        let usage = ticks.flatMap { current in previous.flatMap { current.usage(since: $0) } }
        previous = ticks
        let thermal: String
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: thermal = "Nominal"
        case .fair: thermal = "Fair"
        case .serious: thermal = "Serious"
        case .critical: thermal = "Critical"
        @unknown default: thermal = "Unknown"
        }
        return Metrics(cpu: usage, gpu: GPUUsage.read(), memory: memoryUsage(), swapUsed: swap(),
                       uptime: ProcessInfo.processInfo.systemUptime, thermal: thermal)
    }

    public func resetCPU() { previous = nil }

    private func cpuTicks() -> CPUTicks? {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(host, HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        return CPUTicks(user: info.cpu_ticks.0, system: info.cpu_ticks.1, idle: info.cpu_ticks.2, nice: info.cpu_ticks.3)
    }

    private func memoryUsage() -> MemoryUsage? {
        var info = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(host, HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        var pageSize: vm_size_t = 0
        guard host_page_size(host, &pageSize) == KERN_SUCCESS else { return nil }
        let page = UInt64(pageSize)
        return MemoryUsage(active: UInt64(info.active_count) * page, inactive: UInt64(info.inactive_count) * page,
                           wired: UInt64(info.wire_count) * page, compressed: UInt64(info.compressor_page_count) * page,
                           purgeable: UInt64(info.purgeable_count) * page, external: UInt64(info.external_page_count) * page,
                           total: ProcessInfo.processInfo.physicalMemory)
    }

    private func swap() -> UInt64? {
        var usage = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        guard sysctlbyname("vm.swapusage", &usage, &size, nil, 0) == 0 else { return nil }
        return usage.xsu_used
    }
}
