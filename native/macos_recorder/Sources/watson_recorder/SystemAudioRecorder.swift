import AVFoundation
import CoreMedia
import Foundation
import ScreenCaptureKit

final class SystemAudioRecorder: NSObject, SCStreamOutput, SCStreamDelegate {
    private let outputURL: URL
    private let queue = DispatchQueue(label: "watson.system-audio")
    private var stream: SCStream?
    private var assetWriter: AVAssetWriter?
    private var audioInput: AVAssetWriterInput?
    private var didStartSession = false

    init(outputURL: URL) {
        self.outputURL = outputURL
    }

    func start() async throws {
        let content = try await SCShareableContent.excludingDesktopWindows(
            false,
            onScreenWindowsOnly: true
        )

        guard let display = content.displays.first else {
            throw RuntimeError("No display found for ScreenCaptureKit.")
        }

        let filter = SCContentFilter(display: display, excludingWindows: [])

        let configuration = SCStreamConfiguration()
        configuration.capturesAudio = true
        configuration.excludesCurrentProcessAudio = true
        configuration.sampleRate = 48_000
        configuration.channelCount = 2

        // We do not add a screen output.
        // These tiny dimensions are only here because SCStreamConfiguration expects video-related values.
        configuration.width = 2
        configuration.height = 2
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 1)

        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .m4a)

        let audioSettings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 48_000,
            AVNumberOfChannelsKey: 2,
            AVEncoderBitRateKey: 128_000
        ]

        let input = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
        input.expectsMediaDataInRealTime = true

        guard writer.canAdd(input) else {
            throw RuntimeError("Cannot add audio input to AVAssetWriter.")
        }

        writer.add(input)

        self.assetWriter = writer
        self.audioInput = input

        let stream = SCStream(
            filter: filter,
            configuration: configuration,
            delegate: self
        )

        try stream.addStreamOutput(
            self,
            type: .audio,
            sampleHandlerQueue: queue
        )

        self.stream = stream

        try await stream.startCapture()
    }

    func stop() async throws {
        if let stream {
            try await stream.stopCapture()
        }

        stream = nil

        await finishWriter()
    }

    private func finishWriter() async {
        guard let writer = assetWriter else {
            return
        }

        audioInput?.markAsFinished()

        await withCheckedContinuation { continuation in
            writer.finishWriting {
                continuation.resume()
            }
        }

        assetWriter = nil
        audioInput = nil
        didStartSession = false
    }

    func stream(
        _ stream: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of outputType: SCStreamOutputType
    ) {
        guard outputType == .audio else {
            return
        }

        guard CMSampleBufferDataIsReady(sampleBuffer) else {
            return
        }

        guard let writer = assetWriter, let input = audioInput else {
            return
        }

        if writer.status == .unknown {
            let startTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            writer.startWriting()
            writer.startSession(atSourceTime: startTime)
            didStartSession = true
        }

        guard writer.status == .writing else {
            return
        }

        if input.isReadyForMoreMediaData {
            input.append(sampleBuffer)
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        print("System audio stream stopped with error: \(error)")
    }
}
