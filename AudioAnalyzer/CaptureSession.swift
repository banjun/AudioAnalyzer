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
    @Published private(set) var fftValues: [[Float32]] = []

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


    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        sample = (sampleBuffer, connection)
        guard case .ready = sampleBuffer.dataReadiness else {
            fftValues.removeAll()
            return
        }
        do {
            let channelCount = connection.audioChannels.count
            try sampleBuffer.withAudioBufferList { audioBufferList, blockBuffer in
                guard let asbd = sampleBuffer.formatDescription?.audioStreamBasicDescription else {
                    fftValues.removeAll()
                    return
                }
                let bytesPerChannel = asbd.mBitsPerChannel / 8

                if asbd.mFormatFlags & kAudioFormatFlagIsNonInterleaved > 0 {
                    // audioBufferList has n buffer for n channels, non-interleaved
                    fftValues = audioBufferList.compactMap {$0.mData}.compactMap { mData in
                        let realIn: UnsafePointer<Float32>
                        if asbd.mFormatFlags & kAudioFormatFlagIsFloat > 0, asbd.mBitsPerChannel == 32 {
                            realIn = UnsafePointer(mData.assumingMemoryBound(to: Float32.self))
                        } else {
                            // not yet implemented
                            return nil
                        }
                        let imagIn = [Float32](repeating: 0, count: sampleBuffer.numSamples)
                        var realOut = [Float32](repeating: 0, count: sampleBuffer.numSamples)
                        var imagOut = [Float32](repeating: 0, count: sampleBuffer.numSamples)
                        guard let fftSetup = vDSP_DFT_zop_CreateSetup(nil, vDSP_Length(sampleBuffer.numSamples), .FORWARD) else { return nil }
                        vDSP_DFT_Execute(fftSetup, realIn, imagIn, &realOut, &imagOut)
                        vDSP_DFT_DestroySetup(fftSetup)

                        var complex = realOut.withUnsafeMutableBufferPointer { realOut in
                            imagOut.withUnsafeMutableBufferPointer { imagOut in
                                DSPSplitComplex(realp: realOut.baseAddress!, imagp: imagOut.baseAddress!)
                            }
                        }
                        var magnitudes = [Float32](repeating: 0, count: sampleBuffer.numSamples / 2)
                        vDSP_zvabs(&complex, 1, &magnitudes, 1, vDSP_Length(sampleBuffer.numSamples / 2))
                        var normalizedMagnitudes = [Float32](repeating: 0.0, count: sampleBuffer.numSamples / 2)
                        var scalingFactor = Float(25.0 / (Float(sampleBuffer.numSamples) / 2.0))
                        vDSP_vsmul(&magnitudes, 1, &scalingFactor, &normalizedMagnitudes, 1, vDSP_Length(sampleBuffer.numSamples / 2))

                        return normalizedMagnitudes
                    }
                } else {
                    // audioBufferList has 1 buffer for n channels, interleaved
                    guard let mData = audioBufferList.first?.mData else {
                        fftValues.removeAll()
                        return
                    }

                    if asbd.mFormatFlags & kAudioFormatFlagIsSignedInteger > 0, asbd.mBitsPerChannel == 16 {
                        let source = UnsafeBufferPointer(start: mData.assumingMemoryBound(to: Int16.self), count: sampleBuffer.numSamples * channelCount * Int(bytesPerChannel) / MemoryLayout<Int16>.size)
                            .map {Float32($0) / Float(Int16.max)}
                        fftValues = (0..<channelCount).compactMap { channelIndex in
                            source.withUnsafeBufferPointer { source in
                                let channelSamples = sampleBuffer.numSamples
                                var realIn = [Float32](repeating: 0, count: channelSamples)
                                let imagIn = [Float32](repeating: 0, count: channelSamples)
                                var realOut = [Float32](repeating: 0, count: channelSamples)
                                var imagOut = [Float32](repeating: 0, count: channelSamples)
                                vDSP_vadd(source.baseAddress! + channelIndex, vDSP_Stride(channelCount), realIn, 1, &realIn, 1, vDSP_Length(channelSamples))

                                // copy-and-paste from non-interleaved float32

                                guard let fftSetup = vDSP_DFT_zop_CreateSetup(nil, vDSP_Length(channelSamples), .FORWARD) else { return nil }
                                vDSP_DFT_Execute(fftSetup, realIn, imagIn, &realOut, &imagOut)
                                vDSP_DFT_DestroySetup(fftSetup)

                                var complex = realOut.withUnsafeMutableBufferPointer { realOut in
                                    imagOut.withUnsafeMutableBufferPointer { imagOut in
                                        DSPSplitComplex(realp: realOut.baseAddress!, imagp: imagOut.baseAddress!)
                                    }
                                }
                                var magnitudes = [Float32](repeating: 0, count: channelSamples / 2)
                                vDSP_zvabs(&complex, 1, &magnitudes, 1, vDSP_Length(channelSamples / 2))
                                var normalizedMagnitudes = [Float32](repeating: 0.0, count: channelSamples / 2)
                                var scalingFactor = Float(25.0 / (Float(channelSamples) / 2.0))
                                vDSP_vsmul(&magnitudes, 1, &scalingFactor, &normalizedMagnitudes, 1, vDSP_Length(channelSamples / 2))

                                return normalizedMagnitudes
                            }
                        }
                    } else {
                        // not yet implemented
                        fftValues.removeAll()
                        return
                    }
                }
            }
        } catch {
            // NSLog("%@", "withAudioBufferList error = \(error)")
            fftValues.removeAll()
        }
    }
}
