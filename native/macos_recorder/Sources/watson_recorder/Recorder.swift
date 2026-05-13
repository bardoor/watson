import Foundation

struct RuntimeError: Error, CustomStringConvertible {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var description: String {
        message
    }
}

final class Recorder {
    private let outputDir: URL
    private var microphoneRecorder: MicrophoneRecorder?
    private var systemAudioRecorder: SystemAudioRecorder?

    init(outputDir: URL) {
        self.outputDir = outputDir
    }

    func start() async throws {
        try await Permissions.requestMicrophone()
        try Permissions.requestScreenCapture()

        let micURL = outputDir.appendingPathComponent("mic.m4a")
        let systemURL = outputDir.appendingPathComponent("system.m4a")

        let microphoneRecorder = MicrophoneRecorder(outputURL: micURL)
        let systemAudioRecorder = SystemAudioRecorder(outputURL: systemURL)

        try microphoneRecorder.start()
        try await systemAudioRecorder.start()

        self.microphoneRecorder = microphoneRecorder
        self.systemAudioRecorder = systemAudioRecorder
    }

    func stop() async throws {
        microphoneRecorder?.stop()
        microphoneRecorder = nil

        try await systemAudioRecorder?.stop()
        systemAudioRecorder = nil
    }
}
