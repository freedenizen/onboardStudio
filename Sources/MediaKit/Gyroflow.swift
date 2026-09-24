import CoreServices
import Foundation

/// Gyroflow (https://gyroflow.xyz), run as a separate program to stabilise a video from its gyro
/// data (#263). It is GPLv3, so Onboard Studio never links it: the user installs it, and this starts
/// its command line and reads its progress, as any other program's.
///
/// Measured with Gyroflow 1.6.3 on a HERO13 file: the output keeps the frame count, frame rate,
/// duration and creation time of the input (so a project's sync still holds) but not its GPMF track,
/// which is why only the picture is taken from it.
public enum Gyroflow {
    public static let bundleIdentifier = "xyz.gyroflow"

    /// The command-line program inside the installed app, or `nil` when Gyroflow is not installed.
    public static func executable() -> URL? {
        var candidates: [URL] = []
        if let found = LSCopyApplicationURLsForBundleIdentifier(bundleIdentifier as CFString, nil)?
            .takeRetainedValue() as? [URL]
        {
            candidates += found
        }
        candidates += [
            URL(fileURLWithPath: "/Applications/Gyroflow.app"),
            FileManager.default.homeDirectoryForCurrentUser.appending(path: "Applications/Gyroflow.app"),
        ]
        return candidates.map { $0.appending(path: "Contents/MacOS/gyroflow") }
            .first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    /// Where Gyroflow writes the stabilised copy of `input` in `folder`. Letters, digits, `-` and `_`
    /// only: Gyroflow percent-encodes anything else in the name it is given (1.6.3 wrote
    /// `cut (Gyroflow).mp4` as `cut%20%28Gyroflow%29.mp4`), and the copy would not be found.
    public static func outputURL(for input: URL, in folder: URL) -> URL {
        let base = input.deletingPathExtension().lastPathComponent.unicodeScalars.map { scalar in
            CharacterSet.alphanumerics.contains(scalar) && scalar.isASCII || scalar == "-" || scalar == "_"
                ? String(scalar) : "_"
        }
        return folder.appending(path: base.joined() + "-gyroflow.mp4")
    }

    /// The arguments for stabilising `input` into `folder` at `width` × `height` — the recording's
    /// own size: left to itself Gyroflow crops a 4:3 picture to 16:9. HEVC at `bitrate` Mbit/s, with
    /// the audio, overwriting an earlier copy.
    public static func arguments(input: URL, folder: URL, width: Int, height: Int, bitrate: Int = 100) -> [String] {
        let output = outputURL(for: input, in: folder)
        let parameters = [
            "'codec': 'H.265/HEVC'", "'bitrate': \(bitrate)", "'use_gpu': true", "'audio': true",
            "'output_width': \(width)", "'output_height': \(height)",
            "'output_folder': '\(folder.path)/'", "'output_filename': '\(output.lastPathComponent)'",
        ]
        return [
            input.path, "--overwrite", "--stdout-progress", "--out-params", "{ \(parameters.joined(separator: ", ")) }",
        ]
    }

    /// The fraction done in one line of Gyroflow's progress output
    /// (`[id] Rendering progress: 351/361 frames (97.2%) ETA 0.3s`), or `nil` for any other line.
    public static func progress(in line: String) -> Double? {
        guard let range = line.range(of: "Rendering progress: ") else { return nil }
        let counts = line[range.upperBound...].prefix { $0 != " " }.split(separator: "/")
        guard counts.count == 2, let done = Double(counts[0]), let total = Double(counts[1]), total > 0 else {
            return nil
        }
        return min(max(done / total, 0), 1)
    }

    public enum RunError: Error, CustomStringConvertible, Equatable {
        case notInstalled
        case failed(file: String, status: Int32)
        case noOutput(file: String)

        public var description: String {
            switch self {
            case .notInstalled:
                "Gyroflow is not installed. Install it with “brew install --cask gyroflow” or from gyroflow.xyz."
            case .failed(let file, let status):
                "Gyroflow could not stabilise \(file) (it stopped with code \(status))."
            case .noOutput(let file): "Gyroflow finished without writing a stabilised copy of \(file)."
            }
        }
    }

    /// Stabilises each file of a video in turn into `folder`, reporting the fraction of the whole job
    /// done. The stream ends with the stabilised files, in the same order; cancelling the task that
    /// iterates it stops Gyroflow.
    public static func stabilise(
        _ files: [URL], into folder: URL, width: Int, height: Int
    ) -> AsyncThrowingStream<Double, any Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    guard let executable = executable() else { throw RunError.notInstalled }
                    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                    for (index, file) in files.enumerated() {
                        try Task.checkCancellation()
                        try await run(
                            executable, arguments: arguments(input: file, folder: folder, width: width, height: height),
                            file: file.lastPathComponent
                        ) { fraction in
                            continuation.yield((Double(index) + fraction) / Double(files.count))
                        }
                        let output = outputURL(for: file, in: folder)
                        guard FileManager.default.fileExists(atPath: output.path) else {
                            throw RunError.noOutput(file: file.lastPathComponent)
                        }
                    }
                    continuation.yield(1)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Runs one Gyroflow render, passing its progress on; terminates it if the task is cancelled.
    static func run(
        _ executable: URL, arguments: [String], file: String, progress: @escaping @Sendable (Double) -> Void
    ) async throws {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let text = String(bytes: handle.availableData, encoding: .utf8) ?? ""
            for line in text.split(whereSeparator: \.isNewline) {
                if let fraction = Self.progress(in: String(line)) { progress(fraction) }
            }
        }
        let status: Int32 = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                process.terminationHandler = { continuation.resume(returning: $0.terminationStatus) }
                do { try process.run() } catch { continuation.resume(throwing: error) }
            }
        } onCancel: {
            process.terminate()
        }
        pipe.fileHandleForReading.readabilityHandler = nil
        try Task.checkCancellation()
        guard status == 0 else { throw RunError.failed(file: file, status: status) }
    }
}
