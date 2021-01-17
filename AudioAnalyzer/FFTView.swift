import Cocoa
import Ikemen

final class FFTView: NSView {
    var value: [[Float32]] = [] {
        didSet {
            setNeedsDisplay(bounds)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        dirtyRect.fill(using: .clear)

        let colors: [NSColor] = [
            .systemBlue,
            .systemPurple,
            .systemPink,
            .systemRed,
            .systemOrange,
            .systemYellow,
        ]

        value.enumerated().forEach { channelIndex, magnitudes in
            let barWidth = bounds.width / CGFloat(magnitudes.count)
            colors[channelIndex % colors.count].setFill()
            magnitudes.enumerated().forEach { i, v in
                CGRect(x: CGFloat(i) * barWidth,
                       y: 0,
                       width: barWidth,
                       height: CGFloat(v) * bounds.height).fill(using: .plusLighter)
            }
        }
    }
}
