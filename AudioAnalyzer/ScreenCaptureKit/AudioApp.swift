import Foundation
import ScreenCaptureKit

final class AudioApp {
    static let shared: AudioApp = .init()
    @Published private(set) var apps: [App] = []
    @Published private(set) var display: SCDisplay? // for audio capture, display is required but there are no differences for each displays. we always use the first display.

    struct App: Equatable {
        var scRunningApplication: SCRunningApplication
        var nsRunningApplication: NSRunningApplication

        var name: String { scRunningApplication.applicationName }
        var icon: NSImage? { nsRunningApplication.icon }
        var bundleIdentifier: String { scRunningApplication.bundleIdentifier }
        var processID: pid_t { scRunningApplication.processID }
    }

    private init() {
        reloadApps()
    }

    func reloadApps() {
        SCShareableContent.getExcludingDesktopWindows(true, onScreenWindowsOnly: false) { [weak self] content, error in
            let nsRunningApplications = NSWorkspace.shared.runningApplications
            self?.apps = (content?.applications ?? []).compactMap { sc in
                nsRunningApplications.first {$0.bundleIdentifier == sc.bundleIdentifier}
                    .map {App(scRunningApplication: sc, nsRunningApplication: $0)}
            }
            .sorted { a, b in
                guard a.nsRunningApplication.activationPolicy.rawValue == b.nsRunningApplication.activationPolicy.rawValue else {
                    return a.nsRunningApplication.activationPolicy.rawValue < b.nsRunningApplication.activationPolicy.rawValue
                }
                switch a.name.localizedCaseInsensitiveCompare(b.name) {
                case .orderedAscending: return true
                case .orderedDescending: return false
                case .orderedSame: return a.processID < b.processID
                }
            }
            self?.display = content?.displays.first
        }
    }
}
