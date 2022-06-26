import AVKit
import Combine

final class CaptureSession: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate {
    deinit { NSLog("%@", "deinit \(self.debugDescription)") }

    private let device: AVCaptureDevice
    private let session: AVCaptureSession
    private let input: AVCaptureDeviceInput
    private let output: AVCaptureAudioDataOutput
    private var previewOutput: AVCaptureAudioPreviewOutput? {
        didSet {
            if let oldValue = oldValue {
                session.removeOutput(oldValue)
            }
            if let newValue = previewOutput {
                newValue.volume = previewVolume.value
                session.addOutput(newValue)
            }
        }
    }
    let previewVolume: CurrentValueSubject<Float, Never> = .init(0.5)
    private let audioQueue = DispatchQueue(label: "CaptureSession")

    private var cancellables = Set<AnyCancellable>()

    @Published private(set) var sample: (buffer: CMSampleBuffer, connection: AVCaptureConnection)?
    @Published private(set) var performance: String = "--"
    @Published private(set) var levels: [Float] = []
    var enablesMonitor: Bool = false {
        didSet {
            previewOutput = enablesMonitor ? AVCaptureAudioPreviewOutput() : nil
        }
    }

    private let dft = DFT()
    /// DFT results
    var dftValues: Published<DFT.Result>.Publisher { dft.$result }
    /// DFT sample length
    var sampleBufferForDFTLength: Int {
        get {dft.bufferLength}
        set {dft.bufferLength = newValue}
    }

    init(device: AVCaptureDevice) throws {
        self.device = device
        self.session = AVCaptureSession()
        self.input = try AVCaptureDeviceInput(device: device)
        self.output = AVCaptureAudioDataOutput()
        super.init()

        session.addInput(input)
        output.setSampleBufferDelegate(self, queue: audioQueue)
        session.addOutput(output)
        
        $sample.skipNil().combinePrevious()
            .throttle(for: 0.016, scheduler: DispatchQueue.main, latest: true)
            .sink { [weak self] prev, current in
                guard let self = self else { return }
                let duration = String(format: "%.3f", current.buffer.duration.seconds)
                let prevTime = prev.buffer.outputPresentationTimeStamp.seconds
                let currentTime = current.buffer.outputPresentationTimeStamp.seconds
                let interval = String(format: "%.3f", currentTime - prevTime)
                let format = current.buffer.formatDescription?.audioStreamBasicDescription?.formatDescriptionString ?? "unknown"
                self.performance = "\(current.buffer.numSamples) samples (\(duration) secs) in interval of \(interval) secs, format = [\(format)]"
                self.levels = current.connection.audioChannels.map {$0.averagePowerLevel}
            }.store(in: &cancellables)

        previewVolume.sink {[unowned self] in previewOutput?.volume = $0}
            .store(in: &cancellables)
    }

    func startRunning() {
        session.startRunning()
    }

    func stopRunning() {
        session.stopRunning()
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        sample = (sampleBuffer, connection)
        dft.appendAudioSample(sampleBuffer: sampleBuffer, channelCount: connection.audioChannels.count)
    }
}

import ScreenCaptureKit

final class AppCaptureSession: NSObject, SCStreamOutput {
    private let stream: SCStream

    @Published private(set) var sample: (buffer: CMSampleBuffer, channelCount: Int)?
    @Published private(set) var performance: String = "--"
    @Published private(set) var levels: [Float] = []

    private let dft = DFT()
    /// DFT results
    var dftValues: Published<DFT.Result>.Publisher { dft.$result }
    /// DFT sample length
    var sampleBufferForDFTLength: Int {
        get {dft.bufferLength}
        set {dft.bufferLength = newValue}
    }

    private var cancellables = Set<AnyCancellable>()

    init(app: SCRunningApplication, display: SCDisplay) {
        let c = SCStreamConfiguration()
        c.capturesAudio = true
        c.excludesCurrentProcessAudio = true

        // NOTE: how to disable video capture?
        c.width = 128
        c.height = 128
        c.minimumFrameInterval = .init(value: 1, timescale: 10)

        self.stream = SCStream(filter: SCContentFilter.init(display: display, including: [app], exceptingWindows: []), configuration: c, delegate: nil)
        super.init()

        $sample.skipNil().combinePrevious()
            .throttle(for: 0.016, scheduler: DispatchQueue.main, latest: true)
            .sink { [weak self] prev, current in
                guard let self = self else { return }
                let duration = String(format: "%.3f", current.buffer.duration.seconds)
                let prevTime = prev.buffer.outputPresentationTimeStamp.seconds
                let currentTime = current.buffer.outputPresentationTimeStamp.seconds
                let interval = String(format: "%.3f", currentTime - prevTime)
                let format = current.buffer.formatDescription?.audioStreamBasicDescription?.formatDescriptionString ?? "unknown"
                self.performance = "\(current.buffer.numSamples) samples (\(duration) secs) in interval of \(interval) secs, format = [\(format)]"
                self.levels = (0..<current.channelCount).map {_ in 42} // TODO: $0.averagePowerLevel}
            }.store(in: &cancellables)

        try! self.stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: nil)
    }

    func startRunning() {
        stream.startCapture()
    }

    func stopRunning() {
        stream.stopCapture()
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard sampleBuffer.isValid else { return }
        guard case .audio = type else { return }
        guard let channelCount = sampleBuffer.formatDescription?.audioFormatList.first?.mASBD.mChannelsPerFrame else { return }

        sample = (sampleBuffer, Int(channelCount))
        dft.appendAudioSample(sampleBuffer: sampleBuffer, channelCount: Int(channelCount))
    }
}
