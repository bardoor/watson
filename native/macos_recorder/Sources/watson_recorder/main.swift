import Foundation

enum RuntimeError: Error, CustomStringConvertible {
    case invalidFrame
    case unsupportedFrameType(UInt8)
    case missingCommand
    case unknownCommand(String)

    var description: String {
        switch self {
        case .invalidFrame:
            return "Invalid packet frame."
        case let .unsupportedFrameType(type):
            return "Unsupported frame type: \(type)"
        case .missingCommand:
            return "Missing command field."
        case let .unknownCommand(command):
            return "Unknown command: \(command)"
        }
    }
}

struct CommandEnvelope: Decodable {
    let command: String
    let sessionID: String?
    let microphoneID: String?

    enum CodingKeys: String, CodingKey {
        case command
        case sessionID = "session_id"
        case microphoneID = "microphone_id"
    }
}

final class PacketIO: @unchecked Sendable {
    private let input = FileHandle.standardInput
    private let output = FileHandle.standardOutput
    private let lock = NSLock()

    func readFrame() throws -> Data? {
        let header = try input.read(upToCount: 4) ?? Data()
        if header.isEmpty {
            return nil
        }

        guard header.count == 4 else {
            throw RuntimeError.invalidFrame
        }

        let length = header.withUnsafeBytes { rawBuffer in
            rawBuffer.load(as: UInt32.self).bigEndian
        }

        let payload = try input.read(upToCount: Int(length)) ?? Data()
        guard payload.count == Int(length) else {
            throw RuntimeError.invalidFrame
        }

        return payload
    }

    func writeFrame(_ payload: Data) throws {
        var length = UInt32(payload.count).bigEndian
        let header = Data(bytes: &length, count: MemoryLayout<UInt32>.size)

        lock.lock()
        defer { lock.unlock() }
        try output.write(contentsOf: header)
        try output.write(contentsOf: payload)
    }
}

final class RecorderService {
    private let packetIO = PacketIO()

    func run() async throws {
        let packetIO = self.packetIO

        let recorder = await MainActor.run {
            Recorder(
                emitEvent: { [packetIO] data in
                    try packetIO.writeFrame(data)
                },
                emitAudio: { [packetIO] data in
                    try packetIO.writeFrame(data)
                }
            )
        }

        do {
            while let frame = try packetIO.readFrame() {
                let envelope = try decodeCommandEnvelope(frame)
                try await recorder.handleCommand(envelope)
            }

            try await recorder.shutdownIfNeeded()
        } catch {
            try await recorder.shutdownIfNeeded()
            throw error
        }
    }

    private func decodeCommandEnvelope(_ frame: Data) throws -> CommandEnvelope {
        guard let frameType = frame.first else {
            throw RuntimeError.invalidFrame
        }

        guard frameType == 0x01 else {
            throw RuntimeError.unsupportedFrameType(frameType)
        }

        return try JSONDecoder().decode(CommandEnvelope.self, from: Data(frame.dropFirst()))
    }
}

Task.detached {
    do {
        try await RecorderService().run()
        exit(0)
    } catch {
        fputs("watson-recorder error: \(error)\n", stderr)
        exit(1)
    }
}

dispatchMain()
