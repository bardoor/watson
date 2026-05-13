import Foundation

func parseOutputDir() throws -> URL {
    let args = CommandLine.arguments

    guard let index = args.firstIndex(of: "--output-dir") else {
        throw RuntimeError("Missing required argument: --output-dir")
    }

    let valueIndex = args.index(after: index)

    guard valueIndex < args.endIndex else {
        throw RuntimeError("Missing value for --output-dir")
    }

    let path = args[valueIndex]
    return URL(fileURLWithPath: path, isDirectory: true)
}

let semaphore = DispatchSemaphore(value: 0)

Task {
    do {
        let outputDir = try parseOutputDir()

        try FileManager.default.createDirectory(
            at: outputDir,
            withIntermediateDirectories: true
        )

        let recorder = Recorder(outputDir: outputDir)

        try await recorder.start()

        print("Watson recorder started.")
        print("Writing:")
        print("  \(outputDir.appendingPathComponent("mic.m4a").path)")
        print("  \(outputDir.appendingPathComponent("system.m4a").path)")
        print("Press Ctrl+C in the Watson command to stop recording.")

        while let line = readLine() {
            if line.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "stop" {
                break
            }
        }

        print("Stopping Watson recorder...")
        try await recorder.stop()
        print("Watson recorder stopped.")
        exit(0)
    } catch {
        fputs("watson-recorder error: \(error)\n", stderr)
        exit(1)
    }
}

semaphore.wait()
