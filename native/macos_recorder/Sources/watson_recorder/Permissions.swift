import AVFoundation
import CoreGraphics
import Foundation

enum PermissionError: Error, CustomStringConvertible {
    case microphoneDenied
    case screenCaptureDenied

    var description: String {
        switch self {
        case .microphoneDenied:
            return "Microphone permission was denied."
        case .screenCaptureDenied:
            return "Screen Recording permission was denied. macOS requires it for system audio capture."
        }
    }
}

enum Permissions {
    static func requestMicrophone() async throws {
        let granted = await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                continuation.resume(returning: granted)
            }
        }

        if !granted {
            throw PermissionError.microphoneDenied
        }
    }

    static func requestScreenCapture() throws {
        if CGPreflightScreenCaptureAccess() {
            return
        }

        print("Watson needs Screen Recording permission to capture system audio.")
        print("It does not save video frames. It only writes system audio.")
        print("macOS may open System Settings now.")

        let granted = CGRequestScreenCaptureAccess()

        if !granted {
            throw PermissionError.screenCaptureDenied
        }
    }
}
