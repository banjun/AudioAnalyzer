import AVKit
import Combine

final class CaptureSession: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate {
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
                self.performance = "\(current.buffer.numSamples) samples (\(duration) secs) in interval of \(interval) secs"
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
        self.sample = (sampleBuffer, connection)
    }
}
