import AppKit
import MacZCore

@MainActor
final class DockHistoryView: NSView {
    private var history = DockHistory()
    private var paused = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        autoresizingMask = [.width, .height]
        setAccessibilityElement(true)
        setAccessibilityRole(.image)
    }

    required init?(coder: NSCoder) { nil }

    func show(_ history: DockHistory, paused: Bool) {
        self.history = history
        self.paused = paused
        let cpu = percentage(history.samples.last?.cpu)
        let gpu = percentage(history.samples.last?.gpu)
        setAccessibilityLabel("MacZ. CPU \(cpu), GPU \(gpu). \(paused ? "Paused." : "Last minute, 0 to 100 percent.")")
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.saveGState()
        defer { context.restoreGState() }
        context.scaleBy(x: bounds.width / 128, y: bounds.height / 128)

        let plot = NSRect(x: 2, y: 2, width: 124, height: 124)
        let background = NSBezierPath(roundedRect: plot, xRadius: 12, yRadius: 12)
        NSColor(srgbRed: 0.045, green: 0.065, blue: 0.10, alpha: 1).setFill()
        background.fill()

        context.saveGState()
        background.addClip()
        let cpuColor = NSColor(srgbRed: 0.20, green: 0.60, blue: 1, alpha: 1)
        let gpuColor = NSColor(srgbRed: 1, green: 0.25, blue: 0.28, alpha: 1)
        let cpuPaths = graphPaths(values: history.samples.map(\.cpu), plot: plot)
        let gpuPaths = graphPaths(values: history.samples.map(\.gpu), plot: plot)

        // Additive translucent fills keep the overlap independent of drawing order.
        context.setBlendMode(.plusLighter)
        for (paths, color) in [(cpuPaths, cpuColor), (gpuPaths, gpuColor)] {
            color.withAlphaComponent(paused ? 0.12 : 0.28).setFill()
            paths.fill.fill()
        }
        context.setBlendMode(.normal)
        // Draw both top edges after the fills so neither graph hides the other.
        for (paths, color) in [(cpuPaths, cpuColor), (gpuPaths, gpuColor)] {
            color.withAlphaComponent(paused ? 0.45 : 1).setStroke()
            paths.outline.lineWidth = 1.5
            paths.outline.stroke()
        }
        context.restoreGState()
        NSColor.white.withAlphaComponent(0.18).setStroke()
        background.lineWidth = 0.75
        background.stroke()
    }

    private func graphPaths(values: [Double?], plot: NSRect) -> (fill: NSBezierPath, outline: NSBezierPath) {
        let fill = NSBezierPath()
        let outline = NSBezierPath()
        let step = plot.width / CGFloat(DockHistory.capacity)
        var previousY: CGFloat?
        for (index, value) in values.enumerated() {
            guard let value, value.isFinite else {
                previousY = nil
                continue
            }
            let x = plot.minX + CGFloat(DockHistory.capacity - values.count + index) * step
            let height = CGFloat(min(100, max(0, value))) / 100 * plot.height
            let y = plot.minY + height
            fill.appendRect(NSRect(x: x, y: plot.minY, width: step, height: height))
            if previousY != nil {
                outline.line(to: NSPoint(x: x, y: y))
            } else {
                outline.move(to: NSPoint(x: x, y: y))
            }
            outline.line(to: NSPoint(x: x + step, y: y))
            previousY = y
        }
        return (fill, outline)
    }

    private func percentage(_ value: Double?) -> String {
        value.map { String(format: "%.0f percent", $0) } ?? "unavailable"
    }
}
