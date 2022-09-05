import Accelerate
import CoreMedia

final class DCT: SampleAnalysisAlgorithm {
    @Published private(set) var result: SampleAnalysis.Result = .init(powers: [], sampleRate: 44100)
    var resultPublisher: Published<SampleAnalysis.Result>.Publisher { $result }
    var analysis: SampleAnalysis = .init()

    private var dct: vDSP.DCT?
    /// The window sequence used to reduce spectral leakage.
    /// Apple sample source code https://developer.apple.com/documentation/accelerate/visualizing_sound_as_an_audio_spectrogram
    private var hanningWindow: [Float]?

    func appendAudioSample(sampleBuffer: CMSampleBuffer, channelCount: Int) {
        analysis.appendAudioSample(sampleBuffer: sampleBuffer, channelCount: channelCount, result: &result, reset: {
            self.dct = nil
            self.hanningWindow = nil
        })

        let bufferLength = analysis.bufferLength

        // execute DCT
        guard let dct = self.dct ?? vDSP.DCT(count: bufferLength, transformType: .II) else { return }
        self.dct = dct
        let hanningWindow = self.hanningWindow ?? vDSP.window(ofType: Float.self,
                                                              usingSequence: .hanningDenormalized,
                                                              count: bufferLength,
                                                              isHalfWindow: false)
        self.hanningWindow = hanningWindow
        result.powers = analysis.buffers.map { buffer in
            guard buffer.count >= bufferLength else { return [] }
            var output = buffer
            vDSP.multiply(output, hanningWindow, result: &output)
            dct.transform(output, result: &output)
            vDSP.absolute(output, result: &output)
            // vDSP.convert(amplitude: output, toDecibels: &output, zeroReference: Float(bufferLength))
            // vDSP.add(240, output, result: &output)
            vDSP.multiply(1 / 50, output, result: &output)
            // print(output)
            return output
        }
    }
}
