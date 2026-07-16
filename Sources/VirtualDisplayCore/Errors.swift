import Foundation

public enum StreamError: Error, LocalizedError {
    case privateAPIUnavailable(String), displayCreationFailed, displaySettingsFailed
    case displayRegistrationTimedOut, screenCapturePermissionDenied
    case captureCreationFailed, captureStopped(String), webRTC(String), listener(String), signaling(String)
    case chromiumHelper(String)

    public var errorDescription: String? {
        switch self {
        case .privateAPIUnavailable(let item): "Required private virtual-display API is unavailable: \(item)."
        case .displayCreationFailed: "macOS did not create the virtual display."
        case .displaySettingsFailed: "macOS rejected the virtual display settings."
        case .displayRegistrationTimedOut: "The virtual display did not appear in NSScreen within five seconds."
        case .screenCapturePermissionDenied: "Screen Recording permission is required. Enable it in System Settings > Privacy & Security > Screen Recording, then restart this process."
        case .captureCreationFailed: "ScreenCaptureKit could not find or capture the virtual display."
        case .captureStopped(let reason): "Display capture stopped: \(reason)."
        case .webRTC(let reason): "WebRTC error: \(reason)."
        case .listener(let reason): "HTTP listener error: \(reason)."
        case .signaling(let reason): "Signaling error: \(reason)."
        case .chromiumHelper(let reason): "Chromium streamer error: \(reason)."
        }
    }
}
