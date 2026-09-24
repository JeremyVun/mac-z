import AppKit
import SwiftUI
import MacZCore

enum Page: String, CaseIterable, Identifiable {
    case overview = "Overview", cpu = "CPU", memory = "Memory", graphics = "Graphics", system = "System"
    var id: Self { self }
}

struct ContentView: View {
    @ObservedObject var model: AppModel
    @State private var page: Page = .overview
    private var sampling: Bool { !model.paused }

    var body: some View {
        VStack(spacing: 0) {
            header
            PagePicker(page: $page)
                .padding(.horizontal, 24)
            .padding(.bottom, 18)

            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    switch page {
                    case .overview: overview
                    case .cpu: cpu
                    case .memory: memory
                    case .graphics: graphics
                    case .system: system
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .id(page)
            Divider()
            footer
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .frame(minWidth: 620, minHeight: 570)
        .alert("Couldn't copy report", isPresented: $model.copyFailed) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("The clipboard couldn't be updated. Try copying the report again.")
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            Image(nsImage: AppIcon.image)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: 48, height: 48)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text("MacZ").font(.system(size: 23, weight: .semibold))
                Text("Your Mac, at a glance.").font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text(model.hardware.chip).font(.system(size: 13, weight: .semibold))
                Text("\(model.hardware.model) · \(model.hardware.os)")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
        .padding(20)
    }

    private var overview: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                SummaryTile(label: "PROCESSOR", value: "\(model.hardware.physicalCores) cores", detail: model.hardware.architecture, icon: "cpu")
                SummaryTile(label: "MEMORY", value: Format.bytes(model.hardware.memory), detail: model.hardware.gpus.contains(where: \.unified) ? "Unified memory" : "Physical memory", icon: "memorychip")
                SummaryTile(label: "GRAPHICS", value: model.hardware.gpus.count == 1 ? "1 GPU" : "\(model.hardware.gpus.count) GPUs", detail: "Metal devices", icon: "display")
            }
            HStack(alignment: .top, spacing: 12) {
                ActivityCard(title: "CPU usage", value: cpuValue, detail: "Of total CPU capacity", history: model.cpuHistory, color: .accentColor)
                ActivityCard(title: "Memory used", value: memoryValue, detail: "Of \(Format.bytes(model.hardware.memory)) installed · estimate", history: model.memoryHistory, color: .teal)
            }
            SpecGroup("Current state", specs: [
                Spec("Uptime", model.metrics.map { Format.uptime($0.uptime) } ?? "Unavailable"),
                Spec("Thermal state", model.metrics?.thermal ?? "Unavailable")
            ])
        }
    }

    private var cpu: some View {
        VStack(alignment: .leading, spacing: 18) {
            ActivityCard(title: "CPU usage", value: cpuValue, detail: cpuDetail, history: model.cpuHistory, color: .accentColor)
            SpecGroup("Processor", specs: model.hardware.cpu)
            if !model.hardware.caches.isEmpty { SpecGroup("Caches", specs: model.hardware.caches) }
            note("Cache sizes are reported per core or shared core group by macOS. Live clock speed and CPU temperature aren't available in this version.")
        }
    }

    private var memory: some View {
        VStack(alignment: .leading, spacing: 18) {
            ActivityCard(title: "Memory used", value: memoryValue, detail: "Of \(Format.bytes(model.hardware.memory)) installed · estimate", history: model.memoryHistory, color: .teal)
            SpecGroup("Memory", specs: [
                Spec("Installed", Format.bytes(model.hardware.memory)),
                Spec("Architecture", model.hardware.gpus.contains(where: \.unified) ? "Unified CPU and GPU memory" : "System memory"),
                Spec("Used (estimate)", model.metrics?.memory.map { Format.bytes($0.used) } ?? "Unavailable"),
                Spec("Wired", model.metrics?.memory.map { Format.bytes($0.wired) } ?? "Unavailable"),
                Spec("Compressed", model.metrics?.memory.map { Format.bytes($0.compressed) } ?? "Unavailable"),
                Spec("Swap used", model.metrics?.swapUsed.map(Format.bytes) ?? "Unavailable")
            ])
            note("Used memory is estimated from macOS page counters, excluding file-backed and purgeable pages. It can differ from Activity Monitor. Wired and compressed memory are included in the estimate.")
        }
    }

    private var graphics: some View {
        VStack(alignment: .leading, spacing: 18) {
            SpecGroup("Current activity", specs: [
                Spec("GPU usage", model.metrics?.gpu.map { String(format: "%.1f%%", $0) } ?? "Unavailable")
            ])
            note("The Dock shows CPU and GPU history for the last minute. If multiple GPUs report usage, it shows the busiest one. GPU readings aren't available on every Mac.")
            if model.hardware.gpus.isEmpty {
                ContentUnavailableView("No Metal device found", systemImage: "display", description: Text("macOS hasn't reported a compatible GPU."))
            }
            ForEach(model.hardware.gpus) { gpu in
                SpecGroup(gpu.name, specs: gpu.specs)
            }
            SpecGroup("Connected displays", specs: NSScreen.screens.enumerated().map { index, screen in
                let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
                let mode = number.flatMap { CGDisplayCopyDisplayMode($0.uint32Value) }
                let resolution = mode.map { "\($0.pixelWidth) × \($0.pixelHeight) px" } ?? "Resolution unavailable"
                let refresh = mode.map { $0.refreshRate > 0 ? String(format: " · %.0f Hz", $0.refreshRate) : "" } ?? ""
                return Spec("\(index + 1). \(screen.localizedName)", resolution + refresh)
            })
            note("The recommended working set is Metal's memory budget, not dedicated VRAM. GPU core counts aren't available in this version.")
        }
    }

    private var system: some View {
        VStack(alignment: .leading, spacing: 18) {
            SpecGroup("System", specs: model.hardware.system)
            SpecGroup("Current state", specs: [
                Spec("Uptime", model.metrics.map { Format.uptime($0.uptime) } ?? "Unavailable"),
                Spec("Thermal state", model.metrics?.thermal ?? "Unavailable"),
                Spec("Low Power Mode", ProcessInfo.processInfo.isLowPowerModeEnabled ? "On" : "Off")
            ])
            SpecGroup("MacZ", specs: [Spec("Version", "0.1.0"), Spec("Licence", "MIT"), Spec("Sampling interval", "2 seconds")])
            note("Everything stays on this Mac. Reports omit serial numbers, computer names, usernames and hardware UUIDs. Sampling continues in the background to update the Dock graphs. Pause stops both the window and Dock readings.")
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Circle().fill(sampling ? Color.green : Color.secondary).frame(width: 6, height: 6)
                .accessibilityHidden(true)
            Text(model.paused ? "Paused" : "Live · every 2 seconds")
                .font(.system(size: 11)).foregroundStyle(.secondary)
            Button(model.paused ? "Resume" : "Pause", systemImage: model.paused ? "play.fill" : "pause.fill") { model.paused.toggle() }
                .labelStyle(.iconOnly).buttonStyle(.borderless)
                .help(model.paused ? "Resume live readings" : "Pause live readings")
            Spacer()
            Button { model.copyReport() } label: {
                Label(model.copied ? "Copied" : "Copy report", systemImage: model.copied ? "checkmark" : "doc.on.doc")
            }
            .help("Copy hardware specifications and current readings without device identifiers")
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
    }

    private var cpuValue: String { model.metrics?.cpu.map { String(format: "%.1f%%", $0.total) } ?? "—" }
    private var memoryValue: String { model.metrics?.memory.map { Format.bytes($0.used) } ?? "—" }
    private var cpuDetail: String {
        model.metrics?.cpu.map { String(format: "User %.1f%% · System %.1f%%", $0.user, $0.system) } ?? "Waiting for the next sample"
    }

    private func note(_ text: String) -> some View {
        Text(text).font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
    }
}

// Rebuilding a segmented Picker leaks SwiftUI tag state, so keep it out of the per-sample refresh.
private struct PagePicker: View {
    @Binding var page: Page

    var body: some View {
        Picker("Category", selection: $page) {
            ForEach(Page.allCases) { Text($0.rawValue).tag($0) }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }
}

private struct SummaryTile: View {
    let label: String
    let value: String
    let detail: String
    let icon: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(label).font(.system(size: 9, weight: .semibold)).tracking(1).foregroundStyle(.secondary)
                Spacer()
                Image(systemName: icon).foregroundStyle(.secondary).accessibilityHidden(true)
            }
            Text(value).font(.system(size: 23, weight: .medium, design: .rounded))
            Text(detail).font(.system(size: 11)).foregroundStyle(.secondary)
        }
        .padding(15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.primary.opacity(0.07)))
    }
}

private struct SpecGroup: View {
    let title: String
    let specs: [Spec]
    init(_ title: String, specs: [Spec]) { self.title = title; self.specs = specs }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.system(size: 12, weight: .semibold))
            VStack(spacing: 0) {
                ForEach(Array(specs.enumerated()), id: \.offset) { index, spec in
                    HStack(alignment: .firstTextBaseline, spacing: 16) {
                        Text(spec.label).foregroundStyle(.secondary)
                        Spacer(minLength: 12)
                        Text(spec.value).fontWeight(.medium).multilineTextAlignment(.trailing).textSelection(.enabled)
                    }
                    .font(.system(size: 12))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(index.isMultiple(of: 2) ? Color.primary.opacity(0.025) : .clear)
                }
            }
            .background(.background, in: RoundedRectangle(cornerRadius: 8))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.primary.opacity(0.07)))
        }
    }
}

private struct ActivityCard: View {
    let title: String
    let value: String
    let detail: String
    let history: [Double?]
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.system(size: 12, weight: .semibold))
                Spacer()
                Text(value).font(.system(size: 24, weight: .medium, design: .rounded)).monospacedDigit()
            }
            Text(detail).font(.system(size: 10)).foregroundStyle(.secondary)
            Canvas { context, size in
                for fraction in [0.0, 0.5, 1.0] {
                    var line = Path()
                    line.move(to: CGPoint(x: 0, y: size.height * fraction))
                    line.addLine(to: CGPoint(x: size.width, y: size.height * fraction))
                    context.stroke(line, with: .color(.secondary.opacity(0.14)), style: StrokeStyle(lineWidth: 0.5, dash: [3, 3]))
                }
                guard !history.isEmpty else { return }
                func drawSegment(_ points: [CGPoint]) {
                    guard let first = points.first, let last = points.last else { return }
                    var path = Path()
                    path.addLines(points)
                    var fill = path
                    fill.addLine(to: CGPoint(x: last.x, y: size.height))
                    fill.addLine(to: CGPoint(x: first.x, y: size.height))
                    fill.closeSubpath()
                    context.fill(fill, with: .linearGradient(Gradient(colors: [color.opacity(0.22), color.opacity(0.02)]), startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
                    context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: 1.5, lineJoin: .round))
                    context.fill(Path(ellipseIn: CGRect(x: last.x - 2, y: last.y - 2, width: 4, height: 4)), with: .color(color))
                }
                var points: [CGPoint] = []
                for (index, value) in history.enumerated() {
                    guard let value, value.isFinite else {
                        drawSegment(points)
                        points.removeAll(keepingCapacity: true)
                        continue
                    }
                    points.append(CGPoint(x: size.width * Double(60 - history.count + index) / 59,
                                          y: size.height * (1 - min(100, max(0, value)) / 100)))
                }
                drawSegment(points)
            }
            .frame(height: 45)
            .accessibilityLabel("\(title) history, 0 to 100 percent. Current value: \(value)")
            HStack {
                Text("Last 60 samples")
                Spacer()
                Text("0–100%")
            }.font(.system(size: 9)).foregroundStyle(.tertiary)
        }
        .padding(15)
        .frame(maxWidth: .infinity)
        .background(.background, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.primary.opacity(0.07)))
    }
}
