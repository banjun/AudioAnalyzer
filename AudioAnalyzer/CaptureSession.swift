import AVKit
import Combine
import Accelerate

final class CaptureSession: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate {
    deinit {NSLog("%@", "deinit \(self.debugDescription)")}

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
    @Published private(set) var fftValues: (powers: [[Float32]], sampleRate: Float) = ([], 44100)

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
                let format: String = current.buffer.formatDescription?.audioStreamBasicDescription.map {
                    [
                        String($0.mSampleRate) + "Hz",
                        String($0.mBytesPerFrame) + "bytes/f",
                        String($0.mBitsPerChannel) + "bits/ch",
                        // String($0.mChannelsPerFrame) + "ch/f",
                        $0.mFormatFlags & kAudioFormatFlagIsFloat > 0 ? "Float" : "Integer",
                        $0.mFormatFlags & kAudioFormatFlagIsBigEndian > 0 ? "BE" : "LE",
                        $0.mFormatFlags & kAudioFormatFlagIsSignedInteger > 0 ? "Signed" : "Unsigned",
                        $0.mFormatFlags & kAudioFormatFlagIsPacked > 0 ? "Packed" : "NotPacked",
                        $0.mFormatFlags & kAudioFormatFlagIsAlignedHigh > 0 ? "AlignedHigh" : "AlignedLow",
                        $0.mFormatFlags & kAudioFormatFlagIsNonInterleaved > 0 ? "NonInterleaved" : "Interleaved",
                        $0.mFormatFlags & kAudioFormatFlagIsNonMixable > 0 ? "NonMixable" : "Mixable",
                    ].compactMap {$0}.joined(separator: ", ")
                } ?? "unknown"
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

    /// FFT sample length
    var sampleBufferForFFTLength = 1024
    /// data buffer for FFT as input
    private var sampleBufferForFFT: [[Float32]] = []

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        sample = (sampleBuffer, connection)
        guard case .ready = sampleBuffer.dataReadiness else {
            fftValues.powers.removeAll()
            return
        }
        do {
            let channelCount = connection.audioChannels.count
            let sampleBufferForFFTLength = self.sampleBufferForFFTLength
            let outputBufferForFFTLength = sampleBufferForFFTLength / 2
            if sampleBufferForFFT.count != channelCount || (sampleBufferForFFT.contains {$0.count != sampleBufferForFFTLength}) {
                sampleBufferForFFT = [[Float32]](repeating: [Float32](repeating: 0, count: sampleBufferForFFTLength), count: channelCount)
            }

            try sampleBuffer.withAudioBufferList { audioBufferList, blockBuffer in
                guard let asbd = sampleBuffer.formatDescription?.audioStreamBasicDescription else { return }

                if asbd.mFormatFlags & kAudioFormatFlagIsNonInterleaved > 0 {
                    // audioBufferList has n buffer for n channels, non-interleaved
                    audioBufferList.enumerated().forEach { channelIndex, buffer in
                        // shift & append
                        sampleBufferForFFT[channelIndex].removeFirst(min(Int(sampleBuffer.numSamples), sampleBufferForFFTLength))

                        if asbd.mFormatFlags & kAudioFormatFlagIsFloat > 0, asbd.mBitsPerChannel == 32 {
                            sampleBufferForFFT[channelIndex].append(contentsOf: UnsafeBufferPointer<Float32>(buffer))
                        } else {
                            // not yet implemented
                            return
                        }
                    }
                } else {
                    // audioBufferList has 1 buffer for n channels, interleaved
                    guard let buffer = audioBufferList.first else { return }
                    if asbd.mFormatFlags & kAudioFormatFlagIsSignedInteger > 0, asbd.mBitsPerChannel == 16 {
                        UnsafeBufferPointer<Int16>(buffer).map {Float32($0) / Float(Int16.max)}.withUnsafeBufferPointer { source in
                            // shift & append
                            (0..<channelCount).forEach { channelIndex in
                                sampleBufferForFFT[channelIndex].removeFirst(min(Int(sampleBuffer.numSamples), sampleBufferForFFTLength))

                                var channelSamples = [Float32](repeating: 0, count: sampleBuffer.numSamples)
                                vDSP_vadd(source.baseAddress! + channelIndex, vDSP_Stride(channelCount), channelSamples, 1, &channelSamples, 1, vDSP_Length(sampleBuffer.numSamples))
                                sampleBufferForFFT[channelIndex].append(contentsOf: channelSamples)
                            }
                        }
                    } else {
                        // not yet implemented
                        return
                    }
                }

                // FFT
                fftValues = ((0..<channelCount).map { channelIndex in
                    let realIn = sampleBufferForFFT[channelIndex]
                    let imagIn = [Float32](repeating: 0, count: sampleBufferForFFTLength)
                    var realOut = [Float32](repeating: 0, count: sampleBufferForFFTLength)
                    var imagOut = [Float32](repeating: 0, count: sampleBufferForFFTLength)
                    guard let fftSetup = vDSP_DFT_zop_CreateSetup(nil, vDSP_Length(sampleBufferForFFTLength), .FORWARD) else { return [] }
                    vDSP_DFT_Execute(fftSetup, realIn, imagIn, &realOut, &imagOut)
                    vDSP_DFT_DestroySetup(fftSetup)

                    var complex = realOut.withUnsafeMutableBufferPointer { realOut in
                        imagOut.withUnsafeMutableBufferPointer { imagOut in
                            DSPSplitComplex(realp: realOut.baseAddress!, imagp: imagOut.baseAddress!)
                        }
                    }
                    var magnitudes = [Float32](repeating: 0, count: outputBufferForFFTLength)
                    vDSP_zvabs(&complex, 1, &magnitudes, 1, vDSP_Length(outputBufferForFFTLength))
                    var normalizedMagnitudes = [Float32](repeating: 0.0, count: outputBufferForFFTLength)
                    var scalingFactor = 25.0 / Float(outputBufferForFFTLength)
                    vDSP_vsmul(&magnitudes, 1, &scalingFactor, &normalizedMagnitudes, 1, vDSP_Length(outputBufferForFFTLength))

                    return normalizedMagnitudes
                }, Float(asbd.mSampleRate))
            }
        } catch {
            // NSLog("%@", "withAudioBufferList error = \(error)")
            fftValues.powers.removeAll()
        }
    }
}
