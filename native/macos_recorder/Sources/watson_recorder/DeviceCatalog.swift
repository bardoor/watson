import AVFoundation
import Foundation

final class DeviceCatalog {
    func listDevicesPayload() -> [[String: Any]] {
        let defaultDeviceID = AVCaptureDevice.default(for: .audio)?.uniqueID
        let discoverySession = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone, .external],
            mediaType: .audio,
            position: .unspecified
        )

        return discoverySession.devices.map { device in
            [
                "id": device.uniqueID,
                "name": device.localizedName,
                "is_default": device.uniqueID == defaultDeviceID
            ]
        }
    }
}
