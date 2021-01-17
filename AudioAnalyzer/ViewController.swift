import Cocoa
import NorthLayout
import Ikemen
import Combine

class ViewController: NSViewController {
    deinit {
        NSLog("%@", "deinit \(self.debugDescription)")
    }

    private lazy var audioInputPopup: NSPopUpButton = .init() ※ {
        $0.bind(.selectedIndex, to: self, withKeyPath: #keyPath(selectedIndexOfAudioInputPopup), options: nil)
    }
    @Published @objc private var selectedIndexOfAudioInputPopup: Int = -1 {
        didSet {
            let devices = AudioDevice.shared.inputDevices
            guard case 0..<devices.count = selectedIndexOfAudioInputPopup else { return }
            let device = devices[selectedIndexOfAudioInputPopup]
            title = device.localizedName
            self.session = try? CaptureSession(device: device)
        }
    }

    private let discoversPhonesCheckbox: NSButton = .init(checkboxWithTitle: "Includes Mobiles", target: nil, action: nil)

    private let performanceLabel = NSTextField() ※ {
        $0.isSelectable = true
        $0.drawsBackground = false
        $0.isBezeled = false
        $0.isEditable = false
        $0.maximumNumberOfLines = 0
    }

    private let levelsStackView = ChannelLevelStackView()

    private var session: CaptureSession? {
        didSet {
            oldValue?.stopRunning()
            performanceLabel.stringValue = ""
            levelsStackView.values.removeAll()

            session?.$performance.removeDuplicates().receive(on: RunLoop.main)
                .assign(to: \.stringValue, on: performanceLabel)
                .store(in: &cancellables)

            session?.$levels.removeDuplicates().receive(on: RunLoop.main)
                .map {$0.enumerated().map {(String($0.offset + 1), $0.element)}}
                .assign(to: \.values, on: levelsStackView)
                .store(in: &cancellables)

            session?.startRunning()
        }
    }

    private var cancellables: Set<AnyCancellable> = []

    override func loadView() {
        view = NSView()
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        let autolayout = view.northLayoutFormat(["p": 20], [
            "inputs": audioInputPopup,
            "phones": discoversPhonesCheckbox,
            "performance": performanceLabel ※ {
                $0.setContentCompressionResistancePriority(.init(9), for: .horizontal)
                $0.setContentCompressionResistancePriority(.defaultHigh, for: .vertical)
            },
            "levels": levelsStackView,
        ])
        autolayout("H:|-p-[inputs]-p-[phones]-(>=p)-|")
        autolayout("H:|-p-[performance]-p-|")
        autolayout("H:|-p-[levels]-p-|")
        autolayout("V:|-p-[inputs]-p-[performance]")
        autolayout("V:|-p-[phones(inputs)]-p-[performance]")
        autolayout("V:[performance]-p-[levels]-p-|")

        AudioDevice.shared.$inputDevices
            .prepend(AudioDevice.shared.inputDevices)
            .map {$0.map(\.localizedName)}.sink { [unowned self] names in
                let title = self.audioInputPopup.titleOfSelectedItem
                defer {
                    if let title = title {
                        self.audioInputPopup.selectItem(withTitle: title)
                    } else if !names.isEmpty {
                        self.audioInputPopup.selectItem(at: 0)
                        self.selectedIndexOfAudioInputPopup = 0
                    }
                }

                self.audioInputPopup.removeAllItems()
                self.audioInputPopup.addItems(withTitles: names)
            }.store(in: &cancellables)

        AudioDevice.shared.discoversPhones.map {$0 ? NSControl.StateValue.on : .off}
            .assign(to: \.state, on: discoversPhonesCheckbox)
            .store(in: &cancellables)

        discoversPhonesCheckbox.cell!.publisher(for: \.state, options: [.new])
            .map {
                switch $0 {
                case .on: return true
                default: return false
                }
            }
            .subscribe(AudioDevice.shared.discoversPhones)
            .store(in: &cancellables)
    }
}

