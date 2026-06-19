@preconcurrency import AVFoundation
import CoreMedia
import Foundation

final class SendablePCMBuffer: @unchecked Sendable {
    let buffer: AVAudioPCMBuffer

    init(_ buffer: AVAudioPCMBuffer) {
        self.buffer = buffer
    }
}

final class ConversionState: @unchecked Sendable {
    var consumed = false
}

final class SampleEncoder {
    private let destinationFormats: [AVAudioChannelCount: AVAudioFormat] = [
        1: AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 48_000, channels: 1, interleaved: true)!,
        2: AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 48_000, channels: 2, interleaved: true)!
    ]

    func encode(
        sampleBuffer: CMSampleBuffer,
        expectedChannels: AVAudioChannelCount
    ) throws -> Data {
        guard let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer),
              let destinationFormat = destinationFormats[expectedChannels] else {
            throw NSError(domain: "WatsonRecorder", code: 2, userInfo: [NSLocalizedDescriptionKey: "Unsupported audio format description."])
        }

        let sourceFormat = AVAudioFormat(cmAudioFormatDescription: formatDescription)
        let sourceBuffer = try makeSourceBuffer(sampleBuffer: sampleBuffer, sourceFormat: sourceFormat)

        if sourceFormat == destinationFormat {
            return extractPCMData(buffer: sourceBuffer)
        }

        return try convert(sourceBuffer: sourceBuffer, destinationFormat: destinationFormat)
    }

    private func makeSourceBuffer(
        sampleBuffer: CMSampleBuffer,
        sourceFormat: AVAudioFormat
    ) throws -> AVAudioPCMBuffer {
        var bufferListSizeNeeded = 0
        var blockBuffer: CMBlockBuffer?

        let sizeStatus = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: &bufferListSizeNeeded,
            bufferListOut: nil,
            bufferListSize: 0,
            blockBufferAllocator: nil,
            blockBufferMemoryAllocator: nil,
            flags: 0,
            blockBufferOut: &blockBuffer
        )

        guard sizeStatus == noErr else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(sizeStatus))
        }

        let rawPointer = UnsafeMutableRawPointer.allocate(
            byteCount: bufferListSizeNeeded,
            alignment: MemoryLayout<AudioBufferList>.alignment
        )

        let audioBufferList = rawPointer.bindMemory(to: AudioBufferList.self, capacity: 1)
        defer {
            if blockBuffer == nil {
                rawPointer.deallocate()
            }
        }

        let status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: nil,
            bufferListOut: audioBufferList,
            bufferListSize: bufferListSizeNeeded,
            blockBufferAllocator: nil,
            blockBufferMemoryAllocator: nil,
            flags: kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment,
            blockBufferOut: &blockBuffer
        )

        guard status == noErr else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }

        guard let pcmBuffer = AVAudioPCMBuffer(
            pcmFormat: sourceFormat,
            bufferListNoCopy: audioBufferList,
            deallocator: { _ in
                _ = blockBuffer
                rawPointer.deallocate()
            }
        ) else {
            throw NSError(domain: "WatsonRecorder", code: 3, userInfo: [NSLocalizedDescriptionKey: "Failed to create PCM source buffer."])
        }

        pcmBuffer.frameLength = AVAudioFrameCount(CMSampleBufferGetNumSamples(sampleBuffer))
        return pcmBuffer
    }

    private func convert(sourceBuffer: AVAudioPCMBuffer, destinationFormat: AVAudioFormat) throws -> Data {
        guard let converter = AVAudioConverter(from: sourceBuffer.format, to: destinationFormat),
              let destinationBuffer = AVAudioPCMBuffer(
                pcmFormat: destinationFormat,
                frameCapacity: sourceBuffer.frameLength
              ) else {
            throw NSError(domain: "WatsonRecorder", code: 4, userInfo: [NSLocalizedDescriptionKey: "Failed to create audio converter."])
        }

        let sourceBufferBox = SendablePCMBuffer(sourceBuffer)
        let conversionState = ConversionState()
        var conversionError: NSError?

        let status = converter.convert(to: destinationBuffer, error: &conversionError) { _, outStatus in
            if conversionState.consumed {
                outStatus.pointee = .noDataNow
                return nil
            }

            conversionState.consumed = true
            outStatus.pointee = .haveData
            return sourceBufferBox.buffer
        }

        if let conversionError {
            throw conversionError
        }

        guard status == .haveData || status == .endOfStream else {
            throw NSError(domain: "WatsonRecorder", code: 5, userInfo: [NSLocalizedDescriptionKey: "Audio conversion did not produce PCM data."])
        }

        return extractPCMData(buffer: destinationBuffer)
    }

    private func extractPCMData(buffer: AVAudioPCMBuffer) -> Data {
        let audioBuffer = buffer.audioBufferList.pointee.mBuffers

        guard let data = audioBuffer.mData else {
            return Data()
        }

        return Data(bytes: data, count: Int(audioBuffer.mDataByteSize))
    }
}
