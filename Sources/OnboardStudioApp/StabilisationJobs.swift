import AVFoundation
import Foundation
import MediaKit
import Observation
import ProjectModel

/// Stabilisation work in progress, one job per video input: Gyroflow renders (#263) and measuring the
/// picture's own movement (#264). Kept apart from the inspector so the work goes on while another
/// object is selected, and from `EditorModel`, whose job is the document.
@MainActor @Observable
final class StabilisationJobs {
    static let shared = StabilisationJobs()

    struct Job {
        var progress: Double = 0
        var task: Task<Void, Never>?
        var failure: String?
    }

    private(set) var jobs: [InputID: Job] = [:]

    func job(for input: InputID) -> Job? { jobs[input] }
    func isRunning(_ input: InputID) -> Bool { jobs[input]?.task != nil }

    /// Stabilises every file of `input` with Gyroflow, then points its stabilisation at the copies in
    /// one undoable step. The copies go beside the recording — where Gyroflow itself puts them — or,
    /// when that folder cannot be written to, into Application Support.
    func stabilise(_ input: Input, in editor: EditorModel) {
        guard case .video(let settings) = input.kind, !isRunning(input.id) else { return }
        let location = editor.location
        let files = [location.resolve(input.source)] + settings.clips.map { location.resolve($0.source) }
        let folder = Self.folder(beside: files[0], for: input.id)
        jobs[input.id] = Job()
        let id = input.id
        let task = Task { [weak editor] in
            do {
                let size = try await Self.displaySize(of: files[0])
                for try await fraction in Gyroflow.stabilise(
                    files, into: folder, width: Int(size.width), height: Int(size.height))
                {
                    self.jobs[id]?.progress = fraction
                }
                let copies = files.map { Gyroflow.outputURL(for: $0, in: folder) }
                editor?.updateInput(id, name: "Stabilise with Gyroflow") { input in
                    guard case .video(var video) = input.kind else { return }
                    video.stabilisation.method = .gyroflow
                    video.stabilisation.gyroflowFiles = copies.map {
                        MediaReference.make(for: $0, relativeTo: editor?.fileURL)
                    }
                    input.kind = .video(video)
                }
                self.jobs[id] = nil
            } catch is CancellationError {
                self.jobs[id] = nil
            } catch let error as Gyroflow.RunError {
                self.jobs[id] = Job(progress: 0, task: nil, failure: error.description)
            } catch {
                self.jobs[id] = Job(
                    progress: 0, task: nil,
                    failure: "Gyroflow could not stabilise this video. Try it in the Gyroflow app to see why.")
            }
        }
        jobs[input.id]?.task = task
    }

    /// Measures how the picture of every file of `input` moves (#264), then steadies it from that, in
    /// one undoable step. The measurement is kept, so each file is measured once.
    func measure(_ input: Input, in editor: EditorModel) {
        guard case .video(let settings) = input.kind, !isRunning(input.id) else { return }
        let location = editor.location
        let files = [location.resolve(input.source)] + settings.clips.map { location.resolve($0.source) }
        jobs[input.id] = Job()
        let id = input.id
        let task = Task { [weak editor] in
            do {
                for (index, file) in files.enumerated() where PictureMotion.saved(for: file) == nil {
                    for try await (fraction, _) in PictureMotion.analyse(file) {
                        self.jobs[id]?.progress = (Double(index) + fraction) / Double(files.count)
                    }
                }
                editor?.updateInput(id, name: "Steady from the Picture") { input in
                    guard case .video(var video) = input.kind else { return }
                    video.stabilisation.method = .picture
                    input.kind = .video(video)
                }
                // The measurement is new on disk rather than in the document: load it now.
                editor?.reloadMedia()
                self.jobs[id] = nil
            } catch is CancellationError {
                self.jobs[id] = nil
            } catch {
                self.jobs[id] = Job(
                    progress: 0, task: nil,
                    failure: "The picture's movement could not be measured: the video could not be read.")
            }
        }
        jobs[input.id]?.task = task
    }

    func cancel(_ input: InputID) {
        jobs[input]?.task?.cancel()
        jobs[input] = nil
    }

    /// The folder the recording is in, when it can be written to; else one of the app's own.
    static func folder(beside file: URL, for input: InputID) -> URL {
        let beside = file.deletingLastPathComponent()
        if FileManager.default.isWritableFile(atPath: beside.path) { return beside }
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appending(path: "OnboardStudio/Stabilised/\(input.rawValue.uuidString)")
    }

    /// The picture's size as it is shown: Gyroflow writes it upright, so a camera mounted on its side
    /// gives a tall copy of a wide file.
    static func displaySize(of url: URL) async throws -> CGSize {
        guard let track = try await AVURLAsset(url: url).loadTracks(withMediaType: .video).first else {
            throw Gyroflow.RunError.noOutput(file: url.lastPathComponent)
        }
        let (natural, transform) = try await track.load(.naturalSize, .preferredTransform)
        let shown = natural.applying(transform)
        return CGSize(width: abs(shown.width).rounded(), height: abs(shown.height).rounded())
    }
}

extension EditorModel {
    /// Loads the project's media afresh, for what changed on disk rather than in the document.
    func reloadMedia() { scheduleCompile() }
}
