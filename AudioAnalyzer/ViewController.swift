import Cocoa
import NorthLayout
import Ikemen
import Combine

class ViewController: NSViewController {
    deinit {NSLog("%@", "deinit \(self.debugDescription)")}

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

    private let discoversPhonesCheckbox = NSButton(checkboxWithTitle: "Includes Mobiles", target: nil, action: nil)

    private let performanceLabel = NSTextField() ※ {
        $0.isSelectable = true
        $0.drawsBackground = false
        $0.isBezeled = false
        $0.isEditable = false
        $0.maximumNumberOfLines = 0
    }

    private lazy var monitorCheckbox = NSButton(checkboxWithTitle: "Monitor", target: nil, action: nil) ※ {
        $0.bind(.value, to: monitorVolumeSlider, withKeyPath: #keyPath(NSSlider.isHidden), options: [.valueTransformerName: NSValueTransformerName.negateBooleanTransformerName])
    }
    private lazy var monitorVolumeSlider = NSSlider(value: 0.5, minValue: 0, maxValue: 2, target: nil, action: nil) ※ {
        $0.isHidden = true
        $0.isContinuous = true
        $0.bind(.value, to: self, withKeyPath: #keyPath(monitorVolumeSliderValue), options: nil)
    }
    @Published @objc private var monitorVolumeSliderValue: Float = 0.5

    private let levelsStackView = ChannelLevelStackView()
    private let fftView = FFTView()
    private lazy var fftBufferLengthPopup: NSPopUpButton = .init() ※ {
        $0.bind(.selectedIndex, to: self, withKeyPath: #keyPath(selectedIndexOfFFTBufferLengthPopup), options: nil)
        $0.removeAllItems()
        $0.addItems(withTitles: [256, 512, 1024, 2048, 4096, 8192, 16384].map {String($0)})
        $0.selectItem(at: 2)
    }
    @Published @objc private var selectedIndexOfFFTBufferLengthPopup: Int = 0
    private lazy var fftFrequencyAxisModePopup: NSPopUpButton = .init() ※ {
        $0.bind(.selectedIndex, to: self, withKeyPath: #keyPath(selectedIndexOfFFTFrequencyAxisModePopup), options: nil)
        $0.removeAllItems()
        $0.addItems(withTitles: ["Linear", "MelScale"])
        $0.selectItem(at: 1)
    }
    @Published @objc private var selectedIndexOfFFTFrequencyAxisModePopup: Int = 1

    private lazy var upperFrequencyPopup: NSPopUpButton = .init() ※ {
        $0.bind(.selectedIndex, to: self, withKeyPath: #keyPath(selectedIndexOfUpperFrequencyPopup), options: nil)
        $0.removeAllItems()
        $0.addItems(withTitles: [4410, 8820, 22050, 24000].map {String($0)})
        $0.selectItem(at: 0)
    }
    @Published @objc private var selectedIndexOfUpperFrequencyPopup: Int = 0

    private let estimateMusicalKeysCheckbox = NSButton(checkboxWithTitle: "Keys", target: nil, action: nil)

    private var session: CaptureSession? {
        didSet {
            oldValue?.stopRunning()
            performanceLabel.stringValue = ""
            levelsStackView.values.removeAll()
            monitorCheckbox.state = .off
            monitorVolumeSlider.isHidden = true

            if let session = session {
                session.$performance.removeDuplicates().receive(on: RunLoop.main)
                    .assign(to: \.stringValue, on: performanceLabel)
                    .store(in: &cancellables)

                session.$levels.removeDuplicates().receive(on: DispatchQueue.main)
                    .map {$0.enumerated().map {(String($0.offset + 1), $0.element)}}
                    .assign(to: \.values, on: levelsStackView)
                    .store(in: &cancellables)

                session.$fftValues.receive(on: DispatchQueue.main)
                    .assign(to: \.value, on: fftView)
                    .store(in: &cancellables)

                $selectedIndexOfFFTBufferLengthPopup
                    .map {[unowned self] _ in fftBufferLengthPopup.titleOfSelectedItem.flatMap {Int($0)} ?? 1024}
                    .assign(to: \.sampleBufferForFFTLength, on: session)
                    .store(in: &cancellables)
                session.sampleBufferForFFTLength = fftBufferLengthPopup.titleOfSelectedItem.flatMap {Int($0)} ?? 1024

                session.previewVolume.value = monitorVolumeSliderValue
                $monitorVolumeSliderValue.removeDuplicates()
                    .subscribe(session.previewVolume)
                    .store(in: &cancellables)

                session.startRunning()
            }
        }
    }

    private var cancellables: Set<AnyCancellable> = []

    override func loadView() {
        view = NSView()
        _ = monitorCheckbox
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        let fftBufferLengthLabel = NSTextField(labelWithString: "FFT Buffer") ※ {
            $0.textColor = .tertiaryLabelColor
        }
        let upperLabel = NSTextField(labelWithString: "Upper") ※ {
            $0.textColor = .tertiaryLabelColor
        }

        let autolayout = view.northLayoutFormat(["p": 20], [
            "inputs": audioInputPopup,
            "phones": discoversPhonesCheckbox,
            "performance": performanceLabel ※ {
                $0.setContentCompressionResistancePriority(.init(9), for: .horizontal)
                $0.setContentCompressionResistancePriority(.dragThatCanResizeWindow, for: .vertical)
            },
            "monitorCheckbox": monitorCheckbox,
            "monitorVolume": monitorVolumeSlider,
            "levels": levelsStackView,
            "fft": fftView,
            "fftBufferLengthLabel": fftBufferLengthLabel,
            "fftBufferLengthPopup": fftBufferLengthPopup,
            "fftFrequencyAxisModePopup": fftFrequencyAxisModePopup,
            "upperLabel": upperLabel,
            "upperPopup": upperFrequencyPopup,
            "keys": estimateMusicalKeysCheckbox,
        ])
        autolayout("H:|-p-[inputs]-p-[phones]-(>=p)-|")
        autolayout("H:|-p-[performance]-p-|")
        autolayout("H:|-p-[monitorCheckbox]-p-[monitorVolume]-p-|")
        autolayout("H:|-p-[levels]-p-|")
        autolayout("H:|-p-[fft]-p-|")
        autolayout("H:|-(>=p)-[fftBufferLengthLabel]-[fftBufferLengthPopup]-p-|")
        autolayout("H:|-(>=p)-[fftFrequencyAxisModePopup]-p-|")
        autolayout("H:|-(>=p)-[upperLabel]-[upperPopup]-p-|")
        autolayout("H:|-(>=p)-[keys]-p-|")
        autolayout("H:|-(>=p)-[fftFrequencyAxisModePopup]-p-|")
        autolayout("V:|-p-[inputs]-p-[performance]-p-[monitorCheckbox]-p-[levels]")
        autolayout("V:|-p-[phones(inputs)]-p-[performance]-p-[monitorVolume]-p-[levels]")
        autolayout("V:[levels]-p-[fft(>=128)]-p-|")
        autolayout("V:[levels]-p-[fftBufferLengthPopup]-[fftFrequencyAxisModePopup]-[upperPopup]-[keys]-(>=96)-|")
        fftBufferLengthLabel.centerYAnchor.constraint(equalTo: fftBufferLengthPopup.centerYAnchor).isActive = true
        upperLabel.centerYAnchor.constraint(equalTo: upperFrequencyPopup.centerYAnchor).isActive = true
        [fftBufferLengthLabel, fftBufferLengthPopup, upperLabel, upperFrequencyPopup, estimateMusicalKeysCheckbox].forEach {
            view.addSubview($0, positioned: .above, relativeTo: fftView)
        }

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

        discoversPhonesCheckbox.publisherForStateOnOff()
            .subscribe(AudioDevice.shared.discoversPhones)
            .store(in: &cancellables)

        monitorCheckbox.publisherForStateOnOff()
            .sink { [unowned self] in session?.enablesMonitor = $0 }
            .store(in: &cancellables)

        $selectedIndexOfFFTFrequencyAxisModePopup
            .compactMap {[unowned self] _ -> FFTView.FrequencyAxisMode? in
                switch fftFrequencyAxisModePopup.titleOfSelectedItem {
                case "Linear": return .linear
                case "MelScale": return .melScale
                default: return nil
                }
            }.assign(to: \.frequencyAxisMode, on: fftView)
            .store(in: &cancellables)

        $selectedIndexOfUpperFrequencyPopup
            .compactMap {[unowned self] _ in Float(upperFrequencyPopup.titleOfSelectedItem ?? "")}
            .filter {$0 > 20}
            .assign(to: \.upperFrequency, on: fftView)
            .store(in: &cancellables)

        estimateMusicalKeysCheckbox.publisherForStateOnOff()
            .assign(to: \.estimateMusicalKeys, on: fftView)
            .store(in: &cancellables)
    }
}

