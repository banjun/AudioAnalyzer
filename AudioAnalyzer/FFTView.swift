import Cocoa
import Ikemen
import NorthLayout

private func melScale(_ hz: CGFloat) -> CGFloat {
    CGFloat(1127.010480 * log((hz / 700) + 1))
}
private func keyScale(_ hz: CGFloat) -> CGFloat {
    (12 * (log(hz) / log(2)) / 440) + 9
}

final class FFTView: NSView {
    var value: DFT.Result = .init(powers: [], sampleRate: 44100) {
        didSet {
            let minHz: Float = lowerFrequency
            let maxHz = min(value.sampleRate / 2, upperFrequency)
            graphView.value = (value.powers, value.sampleRate, minHz, maxHz)
            tickView.value = (minHz, maxHz)
            keysView.value = graphView.value
        }
    }

    var upperFrequency: Float = 44100 / 2
    var lowerFrequency: Float = 20

    var estimateMusicalKeys: Bool = false {
        didSet {
            keysView.isEnabled = estimateMusicalKeys
        }
    }

    private var melodyBins: [[Float32]] = [] // TODO

    var frequencyAxisMode: FrequencyAxisMode = .linear {
        didSet {
            graphView.frequencyAxisMode = frequencyAxisMode
            tickView.frequencyAxisMode = frequencyAxisMode
            keysView.frequencyAxisMode = frequencyAxisMode
        }
    }
    enum FrequencyAxisMode {
        case linear
        case melScale
        case keyScale
    }

    private let graphView = FFTGraphView()
    private let tickView = FFTTickView()
    private let keysView = FFTKeysView()

    init() {
        super.init(frame: .zero)
        let autolayout = northLayoutFormat([:], [
            "graph": graphView,
            "tick": tickView,
            "keys": keysView,
        ])
        autolayout("H:|[graph]|")
        autolayout("H:|[tick]|")
        autolayout("H:|[keys]|")
        autolayout("V:|[graph]-2-[tick(16)]-2-[keys(16)]|")
    }
    required init?(coder: NSCoder) {fatalError()}

    static let channelColors: [NSColor] = [
        .systemBlue,
        .systemPurple,
        .systemPink,
        .systemRed,
        .systemOrange,
        .systemYellow,
    ]

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

            let minMelScale: CGFloat = melScale(CGFloat(value.minHz))
            let maxMelScale: CGFloat = melScale(CGFloat(value.maxHz))
            let minKeyScale: CGFloat = keyScale(CGFloat(value.minHz))
            let maxKeyScale: CGFloat = keyScale(CGFloat(value.maxHz))

            value.powers.enumerated().forEach { channelIndex, magnitudes in
                let validMagnitudes = magnitudes.enumerated().filter {
                    value.minHz...value.maxHz ~= Float($0.offset) / Float(magnitudes.count - 1) * value.sampleRate / 2
                }.map {$0.element}
                let hzWidth = (CGFloat(value.sampleRate) / 2) / CGFloat(magnitudes.count - 1)
                FFTView.channelColors[channelIndex % FFTView.channelColors.count].setFill()
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
                    case .keyScale:
                        x = (keyScale(hz) - minKeyScale) / (maxKeyScale - minKeyScale)
                        w = (keyScale(hz + hzWidth) - keyScale(hz)) / (maxKeyScale - minKeyScale)
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
            case .melScale, .keyScale: fallthrough
            case .linear where bounds.width > 1024:
                keyLabels = [
                    minHz,
                    minHz < 400 ? 440 : nil,
                    880,
                    1760,
                    3520,
                    maxHz,
                ].compactMap {$0}
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

            let minMelScale: CGFloat = melScale(minHz)
            let maxMelScale: CGFloat = melScale(maxHz)
            let minKeyScale: CGFloat = keyScale(minHz)
            let maxKeyScale: CGFloat = keyScale(maxHz)

            let attrs: [NSAttributedString.Key: Any] = [.foregroundColor: NSColor.secondaryLabelColor]
            keyLabels.forEach { hz in
                let x: CGFloat
                switch frequencyAxisMode {
                case .linear:
                    x = (hz - minHz) / (maxHz - minHz)
                case .melScale:
                    x = (melScale(hz) - minMelScale) / (maxMelScale - minMelScale)
                case .keyScale:
                    x = (keyScale(hz) - minKeyScale) / (maxKeyScale - minKeyScale)
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

    private class FFTKeysView: NSView {
        fileprivate var value: (powers: [[Float32]], sampleRate: Float, minHz: Float, maxHz: Float) = ([], 44100, 20, 44100 / 2) {
            didSet {
                updateLayers()
            }
        }
        var frequencyAxisMode: FrequencyAxisMode = .linear {
            didSet {
                updateLayers()
            }
        }
        var isEnabled: Bool = false {
            didSet {
                keyBackgroundLayer.isHidden = !isEnabled
                keyBackgroundLayers.forEach {$0.isHidden = !isEnabled}
                if !isEnabled {
                    keyLabelLayers = []
                    keyHighlightLayers = []
                }
            }
        }

        static let labelsWithSharps = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
        static let labelsWithFlats = ["C", "Db", "D", "Eb", "E", "F", "Gb", "G", "Ab", "A", "Bb", "B"]
        static let fundamentalFrequencies: [CGFloat] = (-39...49).map {
            CGFloat(440 * pow(2, (Float($0) - 9) / 12))
        }
        static let fundamentalFrequenciesWithSharps: [(hz: CGFloat, label: String)] = fundamentalFrequencies.enumerated().map {
            ($0.element, labelsWithSharps[($0.offset + 9) % labelsWithSharps.count])
        }
        static let fundamentalFrequenciesWithFlats: [(hz: CGFloat, label: String)] = fundamentalFrequencies.enumerated().map {
            ($0.element, labelsWithFlats[($0.offset + 9) % labelsWithFlats.count])
        }

        let keyBackgroundLayer = CALayer() ※ {
            $0.backgroundColor = .white
        }
        
        var keyLabelLayers: [[CATextLayer]] = [] {
            didSet {
                oldValue.forEach {$0.forEach {$0.removeFromSuperlayer()}}
                keyLabelLayers.forEach {$0.forEach {layer!.addSublayer($0 ※ {$0.zPosition = 1})}}
            }
        }
        private func resetKeyLabelLayers() {
            keyLabelLayers = (0..<value.powers.count).map { channelIndex in
                Self.fundamentalFrequenciesWithFlats.map { hz, label in
                    CATextLayer() ※ {
                        $0.string = label
                        $0.foregroundColor = FFTView.channelColors[channelIndex].cgColor
                        $0.font = NSFont.monospacedSystemFont(ofSize: 14, weight: .semibold)
                        $0.fontSize = 14
                        $0.alignmentMode = .center
                        $0.contentsScale = window?.backingScaleFactor ?? 2
                    }
                }
            }
        }
        private let keyBackgroundLayers: [CALayer] = fundamentalFrequenciesWithFlats.map { hz, label in
            CALayer() ※ {$0.backgroundColor = .init(gray: 0.8, alpha: label.count > 1 ? 1 : 0)}
        }
        private var keyHighlightLayers: [[CALayer]] = [] {
            didSet {
                oldValue.forEach {$0.forEach {$0.removeFromSuperlayer()}}
                keyHighlightLayers.forEach {$0.forEach {layer!.addSublayer($0 ※ {$0.zPosition = 1})}}
            }
        }
        private func resetKeyHighlightLayers() {
            keyHighlightLayers = (0..<value.powers.count).map { channelIndex in
                Self.fundamentalFrequenciesWithFlats.map { hz, label in
                    CALayer() ※ {$0.backgroundColor = FFTView.channelColors[channelIndex].cgColor}
                }
            }
        }

        init() {
            super.init(frame: .zero)
            wantsLayer = true
            layer!.addSublayer(keyBackgroundLayer)
            keyBackgroundLayers.forEach {layer!.addSublayer($0)}
        }
        required init?(coder: NSCoder) {fatalError()}
        
        override var frame: NSRect {
            didSet {
                guard frame.size != oldValue.size else { return }
                updateLayers()
            }
        }
        
        private func updateLayers() {
            guard isEnabled else { return }
            
            CATransaction.begin()
            defer { CATransaction.commit() }
            CATransaction.setDisableActions(true)
            
            if value.powers.count != keyLabelLayers.count {
                resetKeyLabelLayers()
                resetKeyHighlightLayers()
            }

            let minHz = CGFloat(value.minHz)
            let maxHz = CGFloat(value.maxHz)
            let minMelScale: CGFloat = melScale(minHz)
            let maxMelScale: CGFloat = melScale(maxHz)
            let minKeyScale: CGFloat = keyScale(minHz)
            let maxKeyScale: CGFloat = keyScale(maxHz)

            // key index -> channel -> magnitude?
            let keyIndexToMagnitudeForChannels: [[Float?]] = Self.fundamentalFrequencies.map { hz in
                value.powers.map { magnitudes in
                    let binIndex = Int(Float(hz) / (value.sampleRate / 2) * Float(magnitudes.count - 1))
                    return 0..<magnitudes.count ~= binIndex ? magnitudes[binIndex] : nil
                }
            }

            let xws: [(x: CGFloat, w: CGFloat, keyIndex: Int, magnitudeForChannels: [Float?]?)] = zip(Self.fundamentalFrequenciesWithFlats.enumerated(), Self.fundamentalFrequenciesWithFlats.dropFirst()).compactMap { enumerated, next in
                let (i, current) = enumerated
                guard case minHz...maxHz = current.hz else { return nil }

                let x: CGFloat
                let w: CGFloat
                switch frequencyAxisMode {
                case .linear:
                    x = (current.hz - minHz) / (maxHz - minHz)
                    w = (next.hz - current.hz) / (maxHz - minHz)
                case .melScale:
                    x = (melScale(current.hz) - minMelScale) / (maxMelScale - minMelScale)
                    w = (melScale(next.hz) - melScale(current.hz)) / (maxMelScale - minMelScale)
                case .keyScale:
                    x = (keyScale(current.hz) - minKeyScale) / (maxKeyScale - minKeyScale)
                    w = (keyScale(next.hz) - keyScale(current.hz)) / (maxKeyScale - minKeyScale)
                }
                let magnitudeForChannels: [Float?]? = i - 1 >= 0 && 1 + 1 < keyIndexToMagnitudeForChannels.count ? zip(zip(keyIndexToMagnitudeForChannels[i - 1], keyIndexToMagnitudeForChannels[i]), keyIndexToMagnitudeForChannels[i + 1]).map { prevCurrent, next in
                    guard let prev = prevCurrent.0, let current = prevCurrent.1, let next = next else { return nil }
                    return prev < current && current > next ? current : nil
                } : nil
                return (x * (bounds.width - 1), w * (bounds.width - 1), i, magnitudeForChannels)
            }
            
            if let left = xws.first, let right = xws.last {
                keyBackgroundLayer.frame = CGRect(x: left.x, y: 0, width: right.x + right.w, height: bounds.height - 2)
            }

            keyLabelLayers.forEach {$0.forEach {$0.isHidden = true}}
            keyHighlightLayers.forEach {$0.forEach {$0.isHidden = true}}
            keyBackgroundLayers.forEach {$0.isHidden = true}
            xws.forEach { x, w, keyIndex, magnitudeForChannels in
                let backgroundLayer = keyBackgroundLayers[keyIndex]
                backgroundLayer.isHidden = false
                backgroundLayer.frame = CGRect(x: x - w / 2, y: 0, width: w, height: bounds.height - 2)

                (magnitudeForChannels ?? []).enumerated().forEach { i, magnitude in
                    guard let magnitude = magnitude else { return }
                    let textLayer = keyLabelLayers[i][keyIndex]
                    textLayer.isHidden = false
                    textLayer.opacity = magnitude * 10
                    textLayer.frame = CGRect(x: x - 18 / 2, y: 0, width: 18, height: bounds.height)
                    textLayer.transform = CATransform3DMakeScale(min(w, 18) / 18, 1, 1)

                    let highlightLayer = keyHighlightLayers[i][keyIndex]
                    highlightLayer.isHidden = false
                    highlightLayer.opacity = magnitude * 10
                    highlightLayer.frame = CGRect(x: x - w / 2, y: bounds.height - 2, width: w, height: 2)
                }
            }
        }
    }
}
