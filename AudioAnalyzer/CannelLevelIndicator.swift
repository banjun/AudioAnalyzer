import Cocoa
import NorthLayout
import Ikemen

final class ChannelLevelIndicator: NSView {
    var value: (channel: String, levelInDecibel: Float)? {
        didSet {
            channelLabel.stringValue = value?.channel ?? ""
            valueLabel.stringValue = value.map {String(format: "%.1fdB", $0.levelInDecibel)} ?? "--"
            indicator.doubleValue = value.map {Double($0.levelInDecibel)} ?? indicator.minValue
        }
    }

    private let channelLabel = NSTextField(labelWithString: "") ※ {
        $0.font = .monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        $0.alignment = .right
    }
    private let valueLabel = NSTextField(labelWithString: "") ※ {
        $0.font = .monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        $0.alignment = .right
    }

    private let indicator = NSLevelIndicator() ※ {
        $0.levelIndicatorStyle = .continuousCapacity
        $0.minValue = -60
        $0.warningValue = -20
        $0.criticalValue = -10
        $0.maxValue = 0
        // $0.numberOfTickMarks = 7
    }

    init() {
        super.init(frame: .zero)
        let autolayout = northLayoutFormat([:], [
            "channel": channelLabel,
            "indicator": indicator,
            "value": valueLabel,
        ])
        autolayout("H:|[channel(16)]-[indicator]-[value(64)]|")
        autolayout("V:|[indicator]|")
        channelLabel.centerYAnchor.constraint(equalTo: indicator.centerYAnchor).isActive = true
        valueLabel.centerYAnchor.constraint(equalTo: indicator.centerYAnchor).isActive = true
    }
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

final class ChannelLevelStackView: NSView {
    var values: [(channel: String, levelInDecibel: Float)] = [] {
        didSet {
            if values.count != stackView.arrangedSubviews.count {
                stackView.arrangedSubviews.forEach {
                    stackView.removeArrangedSubview($0)
                    $0.removeFromSuperview()
                }

                values.forEach { _ in
                    stackView.addArrangedSubview(ChannelLevelIndicator())
                }
            }

            zip(stackView.arrangedSubviews.map {$0 as! ChannelLevelIndicator}, values).forEach { indicator, value in
                indicator.value = value
            }
            
        }
    }

    private let stackView = NSStackView() ※ {
        $0.orientation = .vertical
    }

    init() {
        super.init(frame: .zero)
        let autolayout = northLayoutFormat([:], ["v": stackView])
        autolayout("H:|[v]|")
        autolayout("V:|[v]|")
        stackView.setHuggingPriority(.required, for: .vertical)
    }
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
