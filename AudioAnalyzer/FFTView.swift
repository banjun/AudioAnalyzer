import Cocoa
import Ikemen
import NorthLayout

final class FFTView: NSView {
    var value: (powers: [[Float32]], sampleRate: Float) = ([], 44100) {
        didSet {
            let minHz: Float = 20
            let maxHz = value.sampleRate / 2
            graphView.value = (value.powers, value.sampleRate, minHz, maxHz)
            tickView.value = (minHz, maxHz)
        }
    }

    private let graphView = FFTGraphView()
    private let tickView = FFTTickView()

    init() {
        super.init(frame: .zero)
        let autolayout = northLayoutFormat([:], [
            "graph": graphView,
            "tick": tickView,
        ])
        autolayout("H:|[graph]|")
        autolayout("H:|[tick]|")
        autolayout("V:|[graph]-4-[tick(16)]|")
    }
    required init?(coder: NSCoder) {fatalError()}

    final class FFTGraphView: NSView {
        fileprivate var value: (powers: [[Float32]], sampleRate: Float, minHz: Float, maxHz: Float) = ([], 44100, 20, 44100 / 2) {
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

            value.powers.enumerated().forEach { channelIndex, magnitudes in
                let validMagnitudes = magnitudes.enumerated().filter {
                    value.minHz...value.maxHz ~= Float($0.offset) / Float(magnitudes.count - 1) * value.sampleRate / 2
                }.map {$0.element}
                let barWidth = bounds.width / CGFloat(validMagnitudes.count)
                colors[channelIndex % colors.count].setFill()
                validMagnitudes.enumerated().forEach { i, v in
                    CGRect(x: CGFloat(i) * barWidth,
                           y: 0,
                           width: barWidth,
                           height: CGFloat(v) * bounds.height).fill(using: .plusLighter)
                }
            }
        }
    }

    final class FFTTickView: NSView {
        fileprivate var value: (minHz: Float, maxHz: Float) = (20, 44100 / 2) {
            didSet {
                guard value != oldValue else { return }
                setNeedsDisplay(bounds)
            }
        }

        private let formatter = NumberFormatter() ※ {
            $0.maximumFractionDigits = 1
        }

        override func draw(_ dirtyRect: NSRect) {
            dirtyRect.fill(using: .clear)

            let labelWidth: CGFloat = 32

            let minHz = CGFloat(value.minHz)
            let maxHz = CGFloat(value.maxHz)
            let keyLabels = [
                minHz,
                //440,
                //880,
                //1760,
                //3520,
                maxHz,
            ]

            let attrs: [NSAttributedString.Key: Any] = [.foregroundColor: NSColor.labelColor]
            keyLabels.forEach { hz in
                let x = hz / (maxHz - minHz) * (bounds.width - labelWidth)
                let hzString = hz >= 1000
                    ? formatter.string(from: (hz / 1000) as NSNumber)! + "k"
                    : formatter.string(from: hz as NSNumber)!
                (hzString as NSString).draw(at: NSPoint(x: x, y: 0), withAttributes: attrs)
            }
        }
    }
}
