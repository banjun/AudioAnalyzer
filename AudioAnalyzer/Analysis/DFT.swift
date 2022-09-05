import Accelerate
import CoreMedia

final class DFT: SampleAnalysisAlgorithm {
    @Published private(set) var result: SampleAnalysis.Result = .init(powers: [], sampleRate: 44100)
    var resultPublisher: Published<SampleAnalysis.Result>.Publisher { $result }
    var analysis: SampleAnalysis = .init()

    /// use DFT instead of FFT at the API level of Accelerate as recommended, expecting the actual call choose FFT if available
    private var dft: vDSP.DiscreteFourierTransform<Float>?

    func appendAudioSample(sampleBuffer: CMSampleBuffer, channelCount: Int) {
        analysis.appendAudioSample(sampleBuffer: sampleBuffer, channelCount: channelCount, result: &result, reset: {
            self.dft = nil
        })

        let bufferLength = analysis.bufferLength
        let outputBufferLength = bufferLength / 2

        // execute DFT
        guard let dft = self.dft ?? (try? vDSP.DiscreteFourierTransform(count: bufferLength, direction: .forward, transformType: .complexReal, ofType: Float.self)) else { return }
        self.dft = dft
        let inputImaginary = [Float32](repeating: 0, count: bufferLength)
        var magnitudes = [Float32](repeating: 0, count: outputBufferLength)
        let scalingFactor = 25.0 / Float(magnitudes.count)
        result.powers = analysis.buffers.map { inputReal in
            guard inputReal.count >= bufferLength else { return [] }
            var output = dft.transform(real: inputReal, imaginary: inputImaginary)
            return output.real.withUnsafeMutableBufferPointer { outputReal in
                output.imaginary.withUnsafeMutableBufferPointer { outputImaginary in
                    let complex = DSPSplitComplex(realp: outputReal.baseAddress!, imagp: outputImaginary.baseAddress!)
                    vDSP.absolute(complex, result: &magnitudes)
                    return vDSP.multiply(scalingFactor, magnitudes)
                }
            }
        }
    }
}
