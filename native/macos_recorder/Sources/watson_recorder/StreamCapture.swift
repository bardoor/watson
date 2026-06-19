import AVFoundation
import CoreMedia
import Foundation
import ScreenCaptureKit

final class StreamCapture: NSObject, SCStreamOutput, SCStreamDelegate {
    private let microphoneID: String?
    private let emitAudio: (Data) throws -> Void
    private let emitError: (String) -> Void
    private let systemQueue = DispatchQueue(label: "watson.stream.system")
    private let microphoneQueue = DispatchQueue(label: "watson.stream.microphone")
    private let sampleEncoder = SampleEncoder()
    private var stream: SCStream?
    private var sessionStartUptimeNs: UInt64?

    init(
        microphoneID: String?,
        emitAudio: @escaping (Data) throws -> Void,
        emitError: @escaping (String) -> Void
    ) {
        self.microphoneID = microphoneID
        self.emitAudio = emitAudio
        self.emitError = emitError
    }

    @MainActor
    func start() async throws {
        let content = try await SCShareableContent.excludingDesktopWindows(
            false,
            onScreenWindowsOnly: true
        )

        guard let display = content.displays.first else {
            throw NSError(domain: "WatsonRecorder", code: 1, userInfo: [NSLocalizedDescriptionKey: "No display available for system audio capture."])
        }

        let filter = SCContentFilter(display: display, excludingWindows: [])
        let configuration = SCStreamConfiguration()
        configuration.capturesAudio = true
        configuration.captureMicrophone = true
        configuration.excludesCurrentProcessAudio = true
        configuration.sampleRate = 48_000
        configuration.channelCount = 2
        configuration.width = 2
        configuration.height = 2
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 1)

        if let microphoneID {
            configuration.microphoneCaptureDeviceID = microphoneID
        }

        let stream = SCStream(
            filter: filter,
            configuration: configuration,
            delegate: self
        )

        try stream.addStreamOutput(
            self,
            type: .audio,
            sampleHandlerQueue: systemQueue
        )

        try stream.addStreamOutput(
            self,
            type: .microphone,
            sampleHandlerQueue: microphoneQueue
        )

        self.stream = stream
        sessionStartUptimeNs = DispatchTime.now().uptimeNanoseconds
        try await stream.startCapture()
    }

    @MainActor
    func stop() async throws {
        if let stream {
            try await stream.stopCapture()
        }

        stream = nil
        sessionStartUptimeNs = nil
    }

    func stream(
        _ stream: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of outputType: SCStreamOutputType
    ) {
        guard CMSampleBufferDataIsReady(sampleBuffer) else {
            return
        }

        do {
            let streamID: UInt8
            let expectedChannels: AVAudioChannelCount

            switch outputType {
            case .microphone:
                streamID = 1
                expectedChannels = 1
            case .audio:
                streamID = 2
                expectedChannels = 2
            default:
                return
            }

            let pcm = try sampleEncoder.encode(
                sampleBuffer: sampleBuffer,
                expectedChannels: expectedChannels
            )

            let timestampUs = currentTimestampUs()
            let payload = framePayload(streamID: streamID, timestampUs: timestampUs, pcm: pcm)
            try emitAudio(payload)
        } catch {
            emitError("audio encode failed: \(error)")
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: any Error) {
        emitError("stream stopped with error: \(error)")
    }

    private func currentTimestampUs() -> UInt64 {
        let now = DispatchTime.now().uptimeNanoseconds
        guard let sessionStartUptimeNs else {
            return 0
        }

        return (now - sessionStartUptimeNs) / 1_000
    }

    private func framePayload(streamID: UInt8, timestampUs: UInt64, pcm: Data) -> Data {
        var payload = Data([0x03, streamID])
        var timestamp = timestampUs.bigEndian
        payload.append(Data(bytes: &timestamp, count: MemoryLayout<UInt64>.size))
        payload.append(pcm)
        return payload
    }
}
