import Foundation
import MediaKit
import Observation
import ProjectModel
import SwiftUI
import TelemetryKit

/// Reading a session's onboard video for traffic (#573), one job per thing the Coaching window
/// reads. Kept apart from the window, so the reading goes on while the window shows another lap.
@MainActor @Observable
final class TrafficVideoJobs {
    static let shared = TrafficVideoJobs()

    struct Job {
        var progress: Double = 0
        var task: Task<Void, Never>?
        var failure: String?
        var finished = false
    }

    private(set) var jobs: [String: Job] = [:]
    /// Moves on each time a reading finishes, so the window reads its lap again with the video.
    private(set) var generation = 0

    func job(for key: String) -> Job? { jobs[key] }

    /// Reads each of `files` not read before, in turn. The readings are kept, so a file is read once.
    func find(in files: [URL], for key: String) {
        guard jobs[key]?.task == nil, !files.isEmpty else { return }
        jobs[key] = Job()
        jobs[key]?.task = Task {
            do {
                var throttle = ProgressThrottle()
                for (index, file) in files.enumerated() where VideoTraffic.saved(for: file) == nil {
                    for try await (fraction, _) in VideoTraffic.analyse(file) {
                        let overall = (Double(index) + fraction) / Double(files.count)
                        if throttle.shouldReport(overall) { self.jobs[key]?.progress = overall }
                    }
                }
                self.jobs[key] = Job(progress: 1, finished: true)
            } catch is CancellationError {
                self.jobs[key] = nil
            } catch {
                self.jobs[key] = Job(
                    failure: "The video could not be read for traffic. Check that its file is still there.")
            }
            self.generation += 1
        }
    }

    func cancel(_ key: String) {
        jobs[key]?.task?.cancel()
        jobs[key] = nil
    }
}

/// Under the coaching: offers to read the session's video for a car close ahead when it has not
/// been read, shows the reading while it runs, and says when it is done (#573).
struct FindTrafficBar: View {
    let source: any CoachingSource
    let input: Input
    private var jobs = TrafficVideoJobs.shared
    /// The session's video files not read yet; `nil` until looked at.
    @State private var unread: [URL]?
    @State private var files: [URL] = []

    init(source: any CoachingSource, input: Input) {
        self.source = source
        self.input = input
    }

    var body: some View {
        let job = jobs.job(for: source.id)
        Group {
            if let job, job.task != nil {
                bar {
                    ProgressView(value: job.progress).frame(maxWidth: 160)
                        .accessibilityLabel("Reading the Video for Traffic")
                        .accessibilityIdentifier("coaching.findTraffic.progress")
                    Text("Reading the video for a car close ahead…").foregroundStyle(.secondary)
                    Spacer()
                    Button("Stop") { jobs.cancel(source.id) }
                        .help("Stop reading the video; what has been read is kept")
                        .accessibilityIdentifier("coaching.findTraffic.stop")
                }
            } else if let failure = job?.failure {
                bar {
                    Label(failure, systemImage: "exclamationmark.triangle").foregroundStyle(.secondary)
                    Spacer()
                    findButton
                }
            } else if let unread, !unread.isEmpty {
                bar {
                    Label(
                        "The video has not been read for traffic. Reading it points at the corners with a car "
                            + "close ahead.", systemImage: "car.2"
                    )
                    .foregroundStyle(.secondary)
                    Spacer()
                    findButton
                }
            } else if job?.finished == true {
                bar {
                    Label("The video has been read for traffic.", systemImage: "checkmark.circle")
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("coaching.findTraffic.done")
                    Spacer()
                }
            }
        }
        .task(id: [source.id, input.id.rawValue.uuidString, "\(jobs.generation)"]) {
            files = source.trafficVideoFiles(for: input)
            let candidates = files
            unread = await Task.detached(priority: .utility) {
                candidates.filter { VideoTraffic.saved(for: $0) == nil }
            }.value
        }
    }

    private var findButton: some View {
        Button("Find Traffic in Video") { jobs.find(in: files, for: source.id) }
            .help("Read the session's video, one picture a second, for a car close ahead in each corner")
            .accessibilityIdentifier("coaching.findTraffic")
    }

    private func bar(@ViewBuilder _ content: () -> some View) -> some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 8) { content() }
                .font(.callout)
                .padding(.horizontal)
                .padding(.vertical, 6)
        }
        .background(.bar)
    }
}

// The video that shows a session (#573): the project's camera, or the Logbook's clips by their clock.
extension ProjectCoachingSource {
    func trafficVideoFiles(for input: Input) -> [URL] {
        guard let editor, let loaded = editor.loaded, let id = editor.project.camera(for: input.id),
            let camera = editor.project.input(id)
        else { return [] }
        return VideoTraffic.files(of: camera, in: loaded)
    }

    func pictureSamples(for input: Input, session: TelemetrySession) -> [PictureSample]? {
        guard let editor, let loaded = editor.loaded, let id = editor.project.camera(for: input.id),
            let camera = editor.project.input(id)
        else { return nil }
        return VideoTraffic.samples(of: camera, for: input, in: loaded)
    }
}

extension LogbookCoachingSource {
    private var recordings: [(files: [URL], recordedAt: Date)] {
        LogbookModel.shared.clips(of: entry).compactMap { clip in
            guard let recordedAt = clip.recordedAt, let first = clip.resolveFile() else { return nil }
            let chapters = clip.chapterPaths.map { URL(fileURLWithPath: $0) }
            return ([first] + chapters, recordedAt)
        }
    }

    func trafficVideoFiles(for input: Input) -> [URL] { recordings.flatMap(\.files) }

    func pictureSamples(for input: Input, session: TelemetrySession) -> [PictureSample]? {
        let read = recordings.compactMap {
            VideoTraffic.samples(ofRecording: $0.files, recordedAt: $0.recordedAt, in: session)
        }
        return read.isEmpty ? nil : read.flatMap { $0 }
    }
}
