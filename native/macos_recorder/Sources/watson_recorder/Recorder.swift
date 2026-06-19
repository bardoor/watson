import Foundation

@MainActor
final class Recorder {
    private let emitEvent: (Data) throws -> Void
    private let emitAudio: (Data) throws -> Void
    private let deviceCatalog = DeviceCatalog()
    private var streamCapture: StreamCapture?
    private var activeSessionID: String?

    init(
        emitEvent: @escaping (Data) throws -> Void,
        emitAudio: @escaping (Data) throws -> Void
    ) {
        self.emitEvent = emitEvent
        self.emitAudio = emitAudio
    }

    func handleCommand(_ envelope: CommandEnvelope) async throws {
        switch envelope.command {
        case "list_devices":
            try emitEvent(eventPayload(name: "devices", fields: ["devices": deviceCatalog.listDevicesPayload()]))

        case "start_session":
            guard streamCapture == nil else {
                try emitEvent(errorEventPayload(reason: "session already active"))
                return
            }

            guard let sessionID = envelope.sessionID else {
                throw RuntimeError.missingCommand
            }

            try await Permissions.requestMicrophone()
            try Permissions.requestScreenCapture()

            let capture = StreamCapture(
                microphoneID: envelope.microphoneID,
                emitAudio: emitAudio,
                emitError: { [weak self] reason in
                    guard let self else {
                        return
                    }

                    try? self.emitEvent(self.errorEventPayload(reason: reason))
                }
            )

            try await capture.start()
            streamCapture = capture
            activeSessionID = sessionID
            try emitEvent(eventPayload(name: "session_started", fields: ["session_id": sessionID]))

        case "stop_session":
            guard let sessionID = envelope.sessionID else {
                throw RuntimeError.missingCommand
            }

            guard let streamCapture, activeSessionID == sessionID else {
                try emitEvent(errorEventPayload(reason: "session not active"))
                return
            }

            try await streamCapture.stop()
            self.streamCapture = nil
            activeSessionID = nil
            try emitEvent(eventPayload(name: "session_stopped", fields: ["session_id": sessionID]))

        default:
            throw RuntimeError.unknownCommand(envelope.command)
        }
    }

    func shutdownIfNeeded() async throws {
        if let streamCapture {
            try await streamCapture.stop()
            self.streamCapture = nil
            activeSessionID = nil
        }
    }

    func errorEventPayload(reason: String) throws -> Data {
        try eventPayload(name: "error", fields: ["reason": reason])
    }

    private func eventPayload(name: String, fields: [String: Any]) throws -> Data {
        var payload = fields
        payload["event"] = name
        let json = try JSONSerialization.data(withJSONObject: payload, options: [])
        return Data([0x02]) + json
    }
}
