import Foundation
import Combine

protocol SessionType: AnyObject {
    var performancePublisher: Published<String>.Publisher { get }
    var levelsPublisher: Published<[Float]>.Publisher { get }
    var dftValues: Published<DFT.Result>.Publisher { get }
    var dctValues: Published<DCT.Result>.Publisher { get }
    var sampleBufferForDFTLength: Int { get set }

    func startRunning()
    func stopRunning()
}

protocol MonitorSessionType: SessionType {
    var previewVolume: CurrentValueSubject<Float, Never> { get }
    var enablesMonitor: Bool { get set }
}
