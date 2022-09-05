import Foundation
import CoreMedia
import Accelerate

protocol SampleAnalysisAlgorithm {
    var resultPublisher: Published<SampleAnalysis.Result>.Publisher { get }
    var analysis: SampleAnalysis { get set }
    func appendAudioSample(sampleBuffer: CMSampleBuffer, channelCount: Int)
}

struct SampleAnalysis {
    var bufferLength = 1024
    var buffers: [[Float32]] = []

    struct Result {
        /// power bins by channels
        var powers: [[Float32]]
        var sampleRate: Float32
    }

    mutating func appendAudioSample(sampleBuffer: CMSampleBuffer, channelCount: Int, result: inout Result, reset: () -> Void) {
        guard case .ready = sampleBuffer.dataReadiness else { return }

        if buffers.count != channelCount || (buffers.contains {$0.count != bufferLength}) {
            buffers = [[Float32]](repeating: [Float32](repeating: 0, count: bufferLength), count: channelCount)
            reset()
        }

        do {
            try sampleBuffer.withAudioBufferList { audioBufferList, blockBuffer in
                defer {
                    // audioBufferList requires free. refs https://daisuke-t-jp.hatenablog.com/entry/2019/10/15/AVCaptureSession
                    // observed as swift_slowAlloc in Malloc 32 Bytes on Instruments
                    free(audioBufferList.unsafeMutablePointer)
                }
                guard let asbd = sampleBuffer.formatDescription?.audioStreamBasicDescription else { return }
                let samplesCount = min(Int(sampleBuffer.numSamples), bufferLength)
                result.sampleRate = .init(asbd.mSampleRate)
                // remove old bufferred samples
                (0..<channelCount).forEach {buffers[$0].removeFirst(samplesCount)}

                // append re-organizing by channels
                if asbd.mFormatFlags & kAudioFormatFlagIsNonInterleaved > 0 {
                    // audioBufferList has n buffer for n channels, non-interleaved
                    audioBufferList.enumerated().forEach { channelIndex, buffer in
                        if asbd.mFormatFlags & kAudioFormatFlagIsFloat > 0, asbd.mBitsPerChannel == 32 {
                            buffers[channelIndex].append(contentsOf: UnsafeBufferPointer<Float32>(buffer).prefix(samplesCount))
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
                                buffers[channelIndex].append(contentsOf: channelSamples)
                            }
                        }
                    } else {
                        // not yet implemented
                        return
                    }
                }
            }
        } catch {
            // NSLog("%@", "withAudioBufferList error = \(error)")
            result.powers.removeAll()
        }
    }
}
