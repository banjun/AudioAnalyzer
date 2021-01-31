import Accelerate
import CoreMedia

final class DFT {
    @Published private(set) var result: Result = .init(powers: [], sampleRate: 44100)
    struct Result {
        /// power bins by channels
        var powers: [[Float32]]
        var sampleRate: Float32
    }

    /// DFT sample length
    var sampleBufferForDFTLength = 1024
    /// data buffer for DFT as input
    private var sampleBufferForDFT: [[Float32]] = []
    /// use DFT instead of FFT at the API level of Accelerate as recommended, expecting the actual call choose FFT if available
    private var dft: vDSP.DFT<Float>?

    func appendAudioSample(sampleBuffer: CMSampleBuffer, channelCount: Int) {
        guard case .ready = sampleBuffer.dataReadiness else {
            result.powers.removeAll()
            return
        }
        do {
            let sampleBufferForDFTLength = self.sampleBufferForDFTLength
            let outputBufferForDFTLength = sampleBufferForDFTLength / 2
            if sampleBufferForDFT.count != channelCount || (sampleBufferForDFT.contains {$0.count != sampleBufferForDFTLength}) {
                sampleBufferForDFT = [[Float32]](repeating: [Float32](repeating: 0, count: sampleBufferForDFTLength), count: channelCount)
                self.dft = nil
            }
            guard let dft = self.dft ?? vDSP.DFT(count: sampleBufferForDFTLength, direction: .forward, transformType: .complexReal, ofType: Float.self) else { return }
            self.dft = dft

            try sampleBuffer.withAudioBufferList { audioBufferList, blockBuffer in
                defer {
                    // audioBufferList requires free. refs https://daisuke-t-jp.hatenablog.com/entry/2019/10/15/AVCaptureSession
                    // observed as swift_slowAlloc in Malloc 32 Bytes on Instruments
                    free(audioBufferList.unsafeMutablePointer)
                }
                guard let asbd = sampleBuffer.formatDescription?.audioStreamBasicDescription else { return }
                let samplesCount = min(Int(sampleBuffer.numSamples), sampleBufferForDFTLength)
                // remove old bufferred samples
                (0..<channelCount).forEach {sampleBufferForDFT[$0].removeFirst(samplesCount)}

                // append re-organizing by channels
                if asbd.mFormatFlags & kAudioFormatFlagIsNonInterleaved > 0 {
                    // audioBufferList has n buffer for n channels, non-interleaved
                    audioBufferList.enumerated().forEach { channelIndex, buffer in
                        if asbd.mFormatFlags & kAudioFormatFlagIsFloat > 0, asbd.mBitsPerChannel == 32 {
                            sampleBufferForDFT[channelIndex].append(contentsOf: UnsafeBufferPointer<Float32>(buffer).prefix(samplesCount))
                        } else {
                            // not yet implemented
                            return
                        }
                    }
                } else {
                    // audioBufferList has 1 buffer for n channels, interleaved
                    guard let buffer = audioBufferList.first else { return }
                    if asbd.mFormatFlags & kAudioFormatFlagIsSignedInteger > 0, asbd.mBitsPerChannel == 16 {
                        vDSP.multiply((1 / Float(Int16.max)), vDSP.integerToFloatingPoint(UnsafeBufferPointer<Int16>(buffer), floatingPointType: Float.self)).withUnsafeBufferPointer { source in
                            (0..<channelCount).forEach { channelIndex in
                                var channelSamples = [Float32](repeating: 0, count: samplesCount)
                                vDSP_vadd(source.baseAddress! + channelIndex, vDSP_Stride(channelCount), channelSamples, 1, &channelSamples, 1, vDSP_Length(samplesCount))
                                sampleBufferForDFT[channelIndex].append(contentsOf: channelSamples)
                            }
                        }
                    } else {
                        // not yet implemented
                        return
                    }
                }

                // execute DFT
                let inputImaginary = [Float32](repeating: 0, count: sampleBufferForDFTLength)
                var magnitudes = [Float32](repeating: 0, count: outputBufferForDFTLength)
                let scalingFactor = 25.0 / Float(magnitudes.count)
                result = .init(powers: sampleBufferForDFT.map { inputReal in
                    var output = dft.transform(inputReal: inputReal, inputImaginary: inputImaginary)
                    return output.real.withUnsafeMutableBufferPointer { outputReal in
                        output.imaginary.withUnsafeMutableBufferPointer { outputImaginary in
                            let complex = DSPSplitComplex(realp: outputReal.baseAddress!, imagp: outputImaginary.baseAddress!)
                            vDSP.absolute(complex, result: &magnitudes)
                            return vDSP.multiply(scalingFactor, magnitudes)
                        }
                    }
                }, sampleRate: .init(asbd.mSampleRate))
            }
        } catch {
            // NSLog("%@", "withAudioBufferList error = \(error)")
            result.powers.removeAll()
        }
    }
}
