import Cocoa
import Ikemen
import NorthLayout

private func melScale(_ hz: CGFloat) -> CGFloat {
    CGFloat(1127.010480 * log((hz / 700) + 1))
}

final class FFTView: NSView {
    var value: (powers: [[Float32]], sampleRate: Float) = ([], 44100) {
        didSet {
            let minHz: Float = 20
//            let maxHz = min(value.sampleRate / 2, 4200)
            let maxHz = value.sampleRate / 2
            graphView.value = (value.powers, value.sampleRate, minHz, maxHz)
            tickView.value = (minHz, maxHz)
        }
    }

    var frequencyAxisMode: FrequencyAxisMode = .linear {
        didSet {
            graphView.frequencyAxisMode = frequencyAxisMode
            tickView.frequencyAxisMode = frequencyAxisMode
        }
    }
    enum FrequencyAxisMode {
        case linear
        case melScale
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
        autolayout("V:|[graph]-2-[tick(16)]|")
    }
    required init?(coder: NSCoder) {fatalError()}

    final class FFTGraphView: NSView {
        fileprivate var value: (powers: [[Float32]], sampleRate: Float, minHz: Float, maxHz: Float) = ([], 44100, 20, 44100 / 2) {
            didSet {
                setNeedsDisplay(bounds)
            }
        }
        var frequencyAxisMode: FrequencyAxisMode = .linear {
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

            let minMelScale = melScale(CGFloat(value.minHz))
            let maxMelScale = melScale(CGFloat(value.maxHz))

            value.powers.enumerated().forEach { channelIndex, magnitudes in
                let validMagnitudes = magnitudes.enumerated().filter {
                    value.minHz...value.maxHz ~= Float($0.offset) / Float(magnitudes.count - 1) * value.sampleRate / 2
                }.map {$0.element}
                let hzWidth = (CGFloat(value.sampleRate) / 2) / CGFloat(magnitudes.count - 1)
                colors[channelIndex % colors.count].setFill()
                validMagnitudes.enumerated().forEach { i, v in
                    let hz = CGFloat(value.minHz) + (CGFloat(i) / CGFloat(magnitudes.count - 1) * CGFloat(value.sampleRate) / 2)
                    let x: CGFloat
                    let w: CGFloat
                    switch frequencyAxisMode {
                    case .linear:
                        x = (hz - CGFloat(value.minHz)) / (CGFloat(value.maxHz) - CGFloat(value.minHz))
                        w = hzWidth / CGFloat(value.maxHz - value.minHz)
                    case .melScale:
                        x = (melScale(hz) - minMelScale) / (maxMelScale - minMelScale)
                        w = (melScale(hz + hzWidth) - melScale(hz)) / (maxMelScale - minMelScale)
                    }
                    CGRect(x: x * (bounds.width - 1),
                           y: 0,
                           width: w * (bounds.width - 1),
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
        var frequencyAxisMode: FrequencyAxisMode = .linear {
            didSet {
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
            let keyLabels: [CGFloat]
            switch frequencyAxisMode {
            case .melScale: fallthrough
            case .linear where bounds.width > 1024:
                keyLabels = [
                    minHz,
                    440,
                    880,
                    1760,
                    3520,
                    maxHz,
                ]
            case .linear where bounds.width > 540:
                keyLabels = [
                    minHz,
                    880,
                    1760,
                    3520,
                    maxHz,
                ]
            case .linear:
                keyLabels = [
                    minHz,
                    3520,
                    maxHz,
                ]
            }

            let minMelScale = melScale(minHz)
            let maxMelScale = melScale(maxHz)

            let attrs: [NSAttributedString.Key: Any] = [.foregroundColor: NSColor.secondaryLabelColor]
            keyLabels.forEach { hz in
                let x: CGFloat
                switch frequencyAxisMode {
                case .linear:
                    x = (hz - minHz) / (maxHz - minHz)
                case .melScale:
                    x = (melScale(hz) - minMelScale) / (maxMelScale - minMelScale)
                }

                NSColor.labelColor.setFill()
                CGRect(x: x * (bounds.width - 1), y: bounds.height - 2, width: 1, height: 2).fill()
                let hzString = hz >= 1000
                    ? formatter.string(from: (hz / 1000) as NSNumber)! + "k"
                    : formatter.string(from: hz as NSNumber)!
                (hzString as NSString).draw(at: CGPoint(x: x * (bounds.width - labelWidth), y: 0), withAttributes: attrs)
            }
        }
    }
}
