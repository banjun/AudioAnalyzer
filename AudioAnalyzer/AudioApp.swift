import Foundation
import ScreenCaptureKit

@available(macOS 12.3, *)
final class AudioApp {
    static let shared: AudioApp = .init()
    @Published private(set) var apps: [SCRunningApplication] = []
    @Published private(set) var displays: [SCDisplay] = []

    private init() {
        SCShareableContent.getExcludingDesktopWindows(true, onScreenWindowsOnly: false) { [weak self] content, error in
            NSLog("%@", "content = \(content), windows = \(content?.windows)")
            self?.displays = content?.displays ?? []
            self?.apps = content?.applications ?? []
            NSLog("%@", "error = \(String(describing: error))")
        }
    }
}
