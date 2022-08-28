import Cocoa
import NorthLayout
import Ikemen
import Combine
import AVKit
import ScreenCaptureKit

class ViewController: NSViewController {
    deinit {NSLog("%@", "deinit \(self.debugDescription)")}

    private lazy var audioInputPopup: NSPopUpButton = .init() ※ {
        $0.bind(.selectedIndex, to: self, withKeyPath: #keyPath(selectedIndexOfAudioInputPopup), options: nil)
    }
    @Published @objc private var selectedIndexOfAudioInputPopup: Int = -1 {
        didSet {
            guard 0..<sourcePopupItems.count ~= selectedIndexOfAudioInputPopup else { return }
            switch sourcePopupItems[selectedIndexOfAudioInputPopup] {
            case .none:
                title = nil
                session = nil
            case .source(let source):
                title = source.title
                switch source {
                case .device(let device):
                    session = try? AVKitCaptureSession(device: device)
                case .system:
                    guard #available(macOS 13.0, *) else { break }
                    session = AudioApp.shared.display.map {ScreenCaptureKitCaptureSession(app: nil, display: $0)}
                case .app(let app):
                    guard #available(macOS 13.0, *) else { break }
                    session = AudioApp.shared.display.map {ScreenCaptureKitCaptureSession(app: app.scRunningApplication, display: $0)}
                }
            case .separator:
                break
            }
        }
    }

    @Published private var sources: [Source] = [] {
        didSet {
            sourcePopupItems = sources.reduce(into: [.none]) { ss, s in
                if case .source(let last) = ss.last, last.caseIdentifier != s.caseIdentifier {
                    // insert separator between different groups
                    ss.append(.separator)
                }
                ss.append(.source(s))
            }
        }
    }
    @Published private var sourcePopupItems: [PopupItem] = [] {
        didSet {
            // preserve selection
            let title = audioInputPopup.titleOfSelectedItem
            defer {
                if let title = title {
                    audioInputPopup.selectItem(withTitle: title)
                }
            }

            audioInputPopup.menu?.removeAllItems()
            sourcePopupItems.forEach {
                switch $0 {
                case .none:
                    audioInputPopup.menu?.addItem(NSMenuItem(title: "", action: nil, keyEquivalent: ""))
                case .source(let source):
                    audioInputPopup.menu?.addItem(NSMenuItem(title: source.title, action: nil, keyEquivalent: "") ※ {$0.image = source.icon})
                case .separator:
                    audioInputPopup.menu?.addItem(NSMenuItem.separator())
                }
            }
        }
    }
    enum PopupItem {
        case none
        case source(Source)
        case separator
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
        $0.font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        $0.addItems(withTitles: [256, 512, 1024, 2048, 4096, 8192, 16384].map {String($0)})
        $0.selectItem(at: 2)
    }
    @Published @objc private var selectedIndexOfFFTBufferLengthPopup: Int = 0
    private lazy var fftFrequencyAxisModePopup: NSPopUpButton = .init() ※ {
        $0.bind(.selectedIndex, to: self, withKeyPath: #keyPath(selectedIndexOfFFTFrequencyAxisModePopup), options: nil)
        $0.removeAllItems()
        $0.addItems(withTitles: ["Linear", "MelScale", "Keyboard"])
        $0.selectItem(at: 1)
    }
    @Published @objc private var selectedIndexOfFFTFrequencyAxisModePopup: Int = 1

    private lazy var upperFrequencyPopup: NSPopUpButton = .init() ※ {
        $0.bind(.selectedIndex, to: self, withKeyPath: #keyPath(selectedIndexOfUpperFrequencyPopup), options: nil)
        $0.removeAllItems()
        $0.font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        $0.addItems(withTitles: [1100, 2205, 4410, 8820, 22050, 24000].map {String($0)})
        $0.selectItem(at: 2)
    }
    @Published @objc private var selectedIndexOfUpperFrequencyPopup: Int = 2
    private lazy var lowerFrequencyPopup: NSPopUpButton = .init() ※ {
        $0.bind(.selectedIndex, to: self, withKeyPath: #keyPath(selectedIndexOfLowerFrequencyPopup), options: nil)
        $0.removeAllItems()
        $0.font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        $0.addItems(withTitles: [20, 100, 200, 400].map {String($0)})
        $0.selectItem(at: 0)
    }
    @Published @objc private var selectedIndexOfLowerFrequencyPopup: Int = 0

    private let estimateMusicalKeysCheckbox = NSButton(checkboxWithTitle: "Keys", target: nil, action: nil)

    private var session: SessionType? {
        didSet {
            sessionCancellables.removeAll()
            oldValue?.stopRunning()
            performanceLabel.stringValue = ""
            levelsStackView.values.removeAll()
            monitorCheckbox.state = .off
            monitorVolumeSlider.isHidden = true

            if let session = session {
                session.performancePublisher.removeDuplicates().receive(on: RunLoop.main)
                    .assign(to: \.stringValue, on: performanceLabel)
                    .store(in: &sessionCancellables)

                session.levelsPublisher.removeDuplicates().receive(on: DispatchQueue.main)
                    .map {$0.enumerated().map {(String($0.offset + 1), $0.element)}}
                    .assign(to: \.values, on: levelsStackView)
                    .store(in: &sessionCancellables)

                session.dctValues.receive(on: DispatchQueue.main)
                    .map {DFT.Result(powers: $0.powers, sampleRate: $0.sampleRate)}
                    .assign(to: \.value, on: fftView)
                    .store(in: &sessionCancellables)
                
                $selectedIndexOfFFTBufferLengthPopup
                    .prepend(0)
                    .map {[unowned self] _ in fftBufferLengthPopup.titleOfSelectedItem.flatMap {Int($0)} ?? 1024}
                    .assign(to: \.sampleBufferForDFTLength, on: session)
                    .store(in: &sessionCancellables)

                if let monitorSession = session as? MonitorSessionType {
                    $monitorVolumeSliderValue
                        .prepend(monitorVolumeSliderValue)
                        .removeDuplicates()
                        .subscribe(monitorSession.previewVolume)
                        .store(in: &sessionCancellables)
                }

                session.startRunning()
            }
        }
    }
    private var sessionCancellables: Set<AnyCancellable> = []

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
        let lowerLabel = NSTextField(labelWithString: "Lower") ※ {
            $0.textColor = .tertiaryLabelColor
        }

        let autolayout = view.northLayoutFormat(["p": 20], [
            "inputs": audioInputPopup ※ {
                $0.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            },
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
            "lowerLabel": lowerLabel,
            "lowerPopup": lowerFrequencyPopup,
            "keys": estimateMusicalKeysCheckbox,
        ])
        autolayout("H:|-p-[inputs(>=128)]-p-[phones]-(>=p)-|")
        autolayout("H:|-p-[performance]-p-|")
        autolayout("H:|-p-[monitorCheckbox]-p-[monitorVolume]-p-|")
        autolayout("H:|-p-[levels]-p-|")
        autolayout("H:|-p-[fft]-p-|")
        autolayout("H:|-(>=p)-[fftBufferLengthLabel]-[fftBufferLengthPopup]-p-|")
        autolayout("H:|-(>=p)-[fftFrequencyAxisModePopup]-p-|")
        autolayout("H:|-(>=p)-[upperLabel]-[upperPopup]-p-|")
        autolayout("H:|-(>=p)-[lowerLabel]-[lowerPopup]-p-|")
        autolayout("H:|-(>=p)-[keys]-p-|")
        autolayout("H:|-(>=p)-[fftFrequencyAxisModePopup]-p-|")
        autolayout("V:|-p-[inputs]-p-[performance]-p-[monitorCheckbox]-p-[levels]")
        autolayout("V:|-p-[phones(inputs)]-p-[performance]-p-[monitorVolume]-p-[levels]")
        autolayout("V:[levels]-p-[fft(>=128)]-p-|")
        autolayout("V:[levels]-p-[fftBufferLengthPopup]-[fftFrequencyAxisModePopup]-[upperPopup]-[lowerPopup]-[keys]-(>=96)-|")
        fftBufferLengthLabel.centerYAnchor.constraint(equalTo: fftBufferLengthPopup.centerYAnchor).isActive = true
        upperLabel.centerYAnchor.constraint(equalTo: upperFrequencyPopup.centerYAnchor).isActive = true
        lowerLabel.centerYAnchor.constraint(equalTo: lowerFrequencyPopup.centerYAnchor).isActive = true
        [fftBufferLengthLabel, fftBufferLengthPopup, upperLabel, upperFrequencyPopup, lowerLabel, lowerFrequencyPopup, estimateMusicalKeysCheckbox].forEach {
            view.addSubview($0, positioned: .above, relativeTo: fftView)
        }

        Publishers.CombineLatest(AudioDevice.shared.$inputDevices, AudioApp.shared.$apps)
            .receive(on: DispatchQueue.main)
            .sink { [unowned self] devices, apps in
                self.sources = [
                    devices.map {.device($0)},
                    apps.isEmpty ? [] : {
                        guard #available(macOS 13.0, *) else { return [] }
                        return [.system]
                    }(),
                    apps.map {.app($0)}
                ].flatMap {$0}
            }.store(in: &cancellables)

        AudioDevice.shared.discoversPhones.map {$0 ? NSControl.StateValue.on : .off}
            .assign(to: \.state, on: discoversPhonesCheckbox)
            .store(in: &cancellables)

        discoversPhonesCheckbox.publisherForStateOnOff()
            .subscribe(AudioDevice.shared.discoversPhones)
            .store(in: &cancellables)

        monitorCheckbox.publisherForStateOnOff()
            .sink { [unowned self] in (session as? MonitorSessionType)?.enablesMonitor = $0 }
            .store(in: &cancellables)

        $selectedIndexOfFFTFrequencyAxisModePopup
            .compactMap {[unowned self] _ -> FFTView.FrequencyAxisMode? in
                switch fftFrequencyAxisModePopup.titleOfSelectedItem {
                case "Linear": return .linear
                case "MelScale": return .melScale
                case "Keyboard": return .keyScale
                default: return nil
                }
            }.assign(to: \.frequencyAxisMode, on: fftView)
            .store(in: &cancellables)

        $selectedIndexOfUpperFrequencyPopup
            .compactMap {[unowned self] _ in Float(upperFrequencyPopup.titleOfSelectedItem ?? "")}
            .filter {$0 >= 20}
            .assign(to: \.upperFrequency, on: fftView)
            .store(in: &cancellables)

        $selectedIndexOfLowerFrequencyPopup
            .compactMap {[unowned self] _ in Float(lowerFrequencyPopup.titleOfSelectedItem ?? "")}
            .filter {$0 >= 20}
            .assign(to: \.lowerFrequency, on: fftView)
            .store(in: &cancellables)

        estimateMusicalKeysCheckbox.publisherForStateOnOff()
            .assign(to: \.estimateMusicalKeys, on: fftView)
            .store(in: &cancellables)
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        if #available(macOS 13, *) {
            AudioApp.shared.reloadApps()
        }
    }
}

