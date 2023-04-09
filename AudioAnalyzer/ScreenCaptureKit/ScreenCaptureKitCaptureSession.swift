import Foundation
import Combine
import ScreenCaptureKit

@available(macOS 13.0, *)
final class ScreenCaptureKitCaptureSession: NSObject, SCStreamOutput, SessionType {
    private let stream: SCStream

    @Published private(set) var sample: (buffer: CMSampleBuffer, channelCount: Int)?
    @Published private(set) var performance: String = "--"
    @Published private(set) var levels: [Float] = []
    var performancePublisher: Published<String>.Publisher { $performance }
    var levelsPublisher: Published<[Float]>.Publisher { $levels }

    private let dft = DFT()
    /// DFT results
    var dftValues: Published<DFT.Result>.Publisher { dft.$result }
    /// DFT sample length
    var sampleBufferForDFTLength: Int {
        get {dft.bufferLength}
        set {dft.bufferLength = newValue}
    }

    private var cancellables = Set<AnyCancellable>()

    init(app: SCRunningApplication?, display: SCDisplay) {
        let c = SCStreamConfiguration()
        c.capturesAudio = true
        c.excludesCurrentProcessAudio = true

        // NOTE: how to disable video capture?
        c.width = 128
        c.height = 128
        c.minimumFrameInterval = .init(value: 1, timescale: 10)

        self.stream = SCStream(filter: app.map {SCContentFilter(display: display, including: [$0], exceptingWindows: [])} ?? SCContentFilter(display: display, excludingWindows: []), configuration: c, delegate: nil)
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
                do {
                    try current.buffer.withAudioBufferList { audioBufferList, blockBuffer in
                        defer {
                            if #available(macOS 13.3, *) {
                                // macOS 13.3 no longer needs free() workaround
                            } else {
                                // audioBufferList requires free. refs https://daisuke-t-jp.hatenablog.com/entry/2019/10/15/AVCaptureSession
                                // observed as swift_slowAlloc in Malloc 32 Bytes on Instruments
                                free(audioBufferList.unsafeMutablePointer)
                            }
                        }
                        let samplesCount = current.buffer.numSamples

                        self.levels = audioBufferList.map { buffer in
                            // mimic average power level of AVFoundation
                            10 * log10f(UnsafeBufferPointer<Float32>(buffer).reduce(into: 0) {$0 += $1 * $1} / Float(samplesCount))
                        }
                    }
                } catch {
                    // NSLog("%@", "error at sampleBuffer.withAudioBufferList: \(String(describing: error))")
                }
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
