import Foundation
import ScreenCaptureKit

@available(macOS 12.3, *)
final class AudioApp {
    static let shared: AudioApp = .init()
    @Published private(set) var apps: [SCRunningApplication] = []
    @Published private(set) var display: SCDisplay? // for audio capture, display is required but there are no differences for each displays. we always use the first display.

    private init() {
        reloadApps()
    }

    func reloadApps() {
        SCShareableContent.getExcludingDesktopWindows(true, onScreenWindowsOnly: false) { [weak self] content, error in
            self?.apps = content?.applications ?? []
            self?.display = content?.displays.first
        }
    }
}
