import Foundation
import Combine

protocol SessionType: AnyObject {
    var performancePublisher: Published<String>.Publisher { get }
    var levelsPublisher: Published<[Float]>.Publisher { get }
    var analysis: SampleAnalysisAlgorithm? { get set }
    var analysisValues: any Publisher<SampleAnalysis.Result, Never> { get }
    var sampleBufferForDFTLength: Int { get set }

    func startRunning()
    func stopRunning()
}

protocol MonitorSessionType: SessionType {
    var previewVolume: CurrentValueSubject<Float, Never> { get }
    var enablesMonitor: Bool { get set }
}
