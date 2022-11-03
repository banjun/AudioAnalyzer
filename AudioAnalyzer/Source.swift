import Foundation
import AVKit
import ScreenCaptureKit

enum Source: Equatable {
    case device(AVCaptureDevice)
    @available(macOS 13.0, *)
    case system
    case app(AudioApp.App)
}

extension Source {
    var caseIdentifier: String {
        switch self {
        case .device: return "device"
        case .system: return "system"
        case .app: return "app"
        }
    }

    var title: String {
        switch self {
        case .device(let device): return device.localizedName
        case .system: return "System Audio"
        case .app(let app): return app.name // + " (\(app.processID))"
        }
    }

    var icon: NSImage? {
        switch self {
        case .device: return nil
        case .system: return nil
        case .app(let app):
            guard let icon = app.icon else { return nil }
            let resized = NSImage(size: NSSize(width: 16, height: 16))
            resized.lockFocus()
            icon.draw(in: NSRect(origin: .zero, size: resized.size))
            resized.unlockFocus()
            return resized
        }
    }
}
