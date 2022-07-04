import Foundation
import AVKit
import Combine
import CoreMediaIO

final class AudioDevice {
    static let shared: AudioDevice = .init()

    @Published private(set) var inputDevices: [AVCaptureDevice] = []
    let discoversPhones: CurrentValueSubject<Bool, Never> = .init(true)
    private var cancellables: Set<AnyCancellable> = []

    private init() {
        Publishers.Merge(NotificationCenter.default.publisher(for: .AVCaptureDeviceWasConnected),
                         NotificationCenter.default.publisher(for: .AVCaptureDeviceWasDisconnected))
            .sink {[weak self] _ in self?.disoverDevices()}.store(in: &cancellables)
        discoversPhones.removeDuplicates().sink { [unowned self] discoversPhones in
            var prop = CMIOObjectPropertyAddress(
                mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyAllowScreenCaptureDevices),
                mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
                mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMaster))
            var allow: UInt32 = discoversPhones ? 1 : 0;
            CMIOObjectSetPropertyData(CMIOObjectID(kCMIOObjectSystemObject), &prop,
                                      0, nil,
                                      UInt32(MemoryLayout.size(ofValue: allow)), &allow)
            disoverDevices()
        }.store(in: &cancellables)
        disoverDevices()
    }

    private func disoverDevices() {
        inputDevices = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInMicrophone, .externalUnknown], mediaType: .none, position: .unspecified).devices
            .filter {$0.hasMediaType(.audio) || $0.hasMediaType(.muxed)}
    }
}
