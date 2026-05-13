import AVFoundation
import Foundation

final class MicrophoneRecorder {
    private let outputURL: URL
    private var recorder: AVAudioRecorder?

    init(outputURL: URL) {
        self.outputURL = outputURL
    }

    func start() throws {
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 48_000,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        let recorder = try AVAudioRecorder(url: outputURL, settings: settings)
        recorder.isMeteringEnabled = false
        recorder.prepareToRecord()

        if !recorder.record() {
            throw RuntimeError("Failed to start microphone recording.")
        }

        self.recorder = recorder
    }

    func stop() {
        recorder?.stop()
        recorder = nil
    }
}
