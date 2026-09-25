import MediaKit
import ProjectModel
import SwiftUI
import TelemetryKit

struct ExportSheet: View {
    @Bindable var editor: EditorModel
    @Environment(\.dismiss) private var dismiss
    @AppStorage(Preferences.defaultExportPreset.key) private var defaultPreset = Preferences.defaultExportPreset.unset
    @State private var preset = "project"
    @State private var settings = ExportSettings()
    @State private var rangeMode = "whole"
    @State private var spanStart = 0.0
    @State private var spanEnd = 0.0
    @State private var firstLap = 1
    @State private var lastLap = 1
    @State private var keyColor = Color.blue
    @State private var progress: ExportProgress?
    @State private var exportTask: Task<Void, Never>?
    @State private var finishedURL: URL?
    @State private var failure: String?
    /// Every-lap export (#150): which laps, and which lap of how many is being written.
    @State private var completeLapsOnly = true
    @State private var skipSlowLaps = false
    @State private var slowLapPercent = 10
    @State private var batchLabel: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Export Video").font(.title2)
            Form {
                Section("Format") {
                    Picker("Preset", selection: $preset) {
                        let size = "\(editor.project.settings.outputWidth) × \(editor.project.settings.outputHeight)"
                        Text("Project size (\(size))").tag("project")
                        ForEach(ExportSettings.namedPresets, id: \.key) { Text($0.name).tag($0.key) }
                        Text("Custom").tag("custom")
                    }
                    .onChange(of: preset) { _, key in applyPreset(key) }
                    HStack {
                        TextField("Width", value: custom(\.width), format: .number)
                        Text("×")
                        TextField("Height", value: custom(\.height), format: .number)
                        Text("px")
                        TextField("fps", value: custom(\.frameRate), format: .number.precision(.fractionLength(0...2)))
                    }
                    Picker("Codec", selection: custom(\.codec)) {
                        ForEach(ExportSettings.VideoCodec.allCases, id: \.self) { Text($0.displayName).tag($0) }
                    }
                    if settings.codec.usesBitrate {
                        SliderField(
                            "Video bitrate",
                            value: Binding(
                                get: { Double(settings.videoBitrate) / 1_000_000 },
                                set: { v in settings.videoBitrate = Int(v * 1_000_000) }),
                            in: 1...80, step: 1, unit: "Mbit/s")
                    }
                    Picker(
                        "Audio",
                        selection: Binding(
                            get: { settings.audioBitrate ?? 0 },
                            set: { v in settings.audioBitrate = v == 0 ? nil : v })
                    ) {
                        Text("None").tag(0)
                        if let current = settings.audioBitrate, !Self.audioBitrates.contains(current) {
                            Text("AAC \(current / 1000) kbit/s").tag(current)
                        }
                        Text("AAC 96 kbit/s").tag(96_000)
                        Text("AAC 128 kbit/s").tag(128_000)
                        Text("AAC 192 kbit/s").tag(192_000)
                        Text("AAC 256 kbit/s").tag(256_000)
                        Text("AAC 320 kbit/s").tag(320_000)
                    }
                    if settings.audioBitrate != nil {
                        Picker("Audio channels", selection: custom(\.audioChannels)) {
                            Text("Mono").tag(1)
                            Text("Stereo").tag(2)
                        }
                    }
                }
                Section("360°") {
                    Toggle("Tag as 360° video (spherical metadata)", isOn: custom(\.spherical))
                    Text("For full equirectangular frames (lens unwrap off); players and YouTube show a panorama.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("Background") {
                    Picker("Behind the overlays", selection: backgroundMode) {
                        Text("Video").tag("video")
                        Text("Key colour (no video)").tag("key")
                        Text("Transparent (no video, alpha codec)").tag("transparent")
                    }
                    if case .keyColor = settings.background {
                        ColorPicker("Key colour", selection: $keyColor, supportsOpacity: false)
                            .onChange(of: keyColor) { _, c in settings.background = .keyColor(RGBAColor(c)) }
                    }
                }
                Section("Range") {
                    Picker("Export", selection: $rangeMode) {
                        Text("Whole project").tag("whole")
                        Text("Time span").tag("span")
                        if let range = editor.inOutRange {
                            Text(
                                "In to out (\(TimeParsing.lapTimeString(range.lowerBound)) – "
                                    + "\(TimeParsing.lapTimeString(range.upperBound)))"
                            )
                            .tag("inout")
                        }
                        Text("Laps").tag("laps").disabled(lapCount == 0)
                        Text("Every lap, one file each").tag("eachLap").disabled(lapCount == 0)
                    }
                    if rangeMode == "eachLap" { eachLapOptions }
                    if rangeMode == "span" {
                        HStack {
                            TextField("From (s)", value: $spanStart, format: .number.precision(.fractionLength(0...2)))
                            TextField("To (s)", value: $spanEnd, format: .number.precision(.fractionLength(0...2)))
                            Button("Use Playhead as Start") { spanStart = editor.currentTime }
                        }
                    }
                    if rangeMode == "laps" {
                        HStack {
                            Stepper(
                                "First lap: \(firstLap)", value: $firstLap,
                                in: lapNumbers.lowerBound...lapNumbers.upperBound)
                            Stepper(
                                "Last lap: \(lastLap)", value: $lastLap,
                                in: lapNumbers.lowerBound...lapNumbers.upperBound)
                        }
                        if let range = resolvedRange {
                            let from = TimeParsing.lapTimeString(range.lowerBound)
                            let to = TimeParsing.lapTimeString(range.upperBound)
                            Text("\(from) – \(to)").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .frame(height: 460)
            if let progress {
                ProgressView(value: progress.fraction) {
                    Text(
                        finishedURL == nil
                            ? batchLabel ?? "Exporting… \(progress.framesWritten) frames"
                            : "Done: \(finishedURL?.lastPathComponent ?? "")")
                }
            }
            if let failure { Text(failure).foregroundStyle(.red) }
            HStack {
                Spacer()
                if exportTask != nil {
                    Button("Cancel") { exportTask?.cancel() }
                } else {
                    Button("Close") { dismiss() }.keyboardShortcut(.cancelAction).accessibilityIdentifier(
                        "export.close")
                    if let finishedURL {
                        Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([finishedURL]) }
                            .accessibilityIdentifier("export.reveal")
                        if !finishedURL.hasDirectoryPath {
                            Button("Upload to YouTube…") {
                                dismiss()
                                editor.uploadURL = finishedURL
                            }
                        }
                    }
                    Button("Export…") { start() }.keyboardShortcut(.defaultAction).accessibilityIdentifier(
                        "export.start")
                }
            }
        }
        .padding(20)
        .frame(width: 560)
        .onAppear(perform: load)
    }

    static let audioBitrates = [96_000, 128_000, 192_000, 256_000, 320_000]

    // MARK: - State

    func load() {
        settings = editor.project.export.reconciled
        settings.frameRate = editor.project.settings.frameRate
        preset = ExportSettings.namedPresets.first { $0.settings == editor.project.export }?.key ?? defaultPreset
        if preset == "project" || ExportSettings.presets[preset] == nil {
            applyPreset("project")
        } else {
            applyPreset(preset)
        }
        switch settings.range {
        case .whole: rangeMode = "whole"
        case .span(let s, let e):
            rangeMode = "span"
            spanStart = s
            spanEnd = e
        case .laps(let f, let l):
            rangeMode = "laps"
            firstLap = f
            lastLap = l
        case .eachLap(let completeOnly, let slowerThanBest):
            rangeMode = "eachLap"
            completeLapsOnly = completeOnly
            skipSlowLaps = slowerThanBest != nil
            if let slowerThanBest { slowLapPercent = Int((slowerThanBest * 100).rounded()) }
        }
        if spanEnd == 0 { spanEnd = editor.duration }
        // A range marked with I and O is what the user means to export, as in any editor (#230).
        if editor.inOutRange != nil { rangeMode = "inout" }
        if case .keyColor(let c) = settings.background { keyColor = Color(c) }
        if lapCount > 0 {
            firstLap = min(max(firstLap, lapNumbers.lowerBound), lapNumbers.upperBound)
            lastLap = min(max(lastLap, firstLap), lapNumbers.upperBound)
        }
    }

    func applyPreset(_ key: String) {
        guard key != "custom" else { return }
        let background = settings.background
        let range = settings.range
        let audio = settings.audioBitrate
        if key == "project" {
            settings.width = editor.project.settings.outputWidth
            settings.height = editor.project.settings.outputHeight
        } else if let chosen = ExportSettings.presets[key] {
            settings = chosen
            settings.range = range
            if !chosen.background.isOverlayOnly {
                settings.background = background
                settings.audioBitrate = audio
            }
        }
        settings.frameRate = editor.project.settings.frameRate
        settings = settings.reconciled
    }

    /// A binding into `settings` that switches the preset picker to Custom when edited.
    func custom<T: Equatable>(_ keyPath: WritableKeyPath<ExportSettings, T>) -> Binding<T> {
        Binding(
            get: { settings[keyPath: keyPath] },
            set: { value in
                // Text fields commit their formatted value when focused; only a real change is custom.
                guard settings[keyPath: keyPath] != value else { return }
                settings[keyPath: keyPath] = value
                settings = settings.reconciled
                preset = "custom"
            })
    }

    var backgroundMode: Binding<String> {
        Binding(
            get: {
                switch settings.background {
                case .video: "video"
                case .keyColor: "key"
                case .transparent: "transparent"
                }
            },
            set: { mode in
                switch mode {
                case "key": settings.background = .keyColor(RGBAColor(keyColor))
                case "transparent":
                    settings.background = .transparent
                    if !settings.codec.supportsAlpha { settings.codec = .proRes4444 }
                default: settings.background = .video
                }
                preset = "custom"
            })
    }
}

extension ExportSheet {
    var lapSession: TelemetrySession? {
        editor.project.dataInputs.lazy.compactMap { editor.sessions[$0.id] }.first { !$0.laps.isEmpty }
    }
    var lapCount: Int { lapSession?.laps.count ?? 0 }
    var lapNumbers: ClosedRange<Int> {
        let numbers = lapSession?.laps.map(\.number) ?? []
        return (numbers.min() ?? 0)...(numbers.max() ?? 0)
    }

    var finalSettings: ExportSettings {
        var s = settings.reconciled
        switch rangeMode {
        case "span": s.range = .span(start: spanStart, end: spanEnd)
        case "inout":
            if let range = editor.inOutRange { s.range = .span(start: range.lowerBound, end: range.upperBound) }
        case "laps": s.range = .laps(first: firstLap, last: lastLap)
        case "eachLap":
            s.range = .eachLap(
                completeOnly: completeLapsOnly, slowerThanBest: skipSlowLaps ? Double(slowLapPercent) / 100 : nil)
        default: s.range = .whole
        }
        s.width -= s.width % 2
        s.height -= s.height % 2
        return s
    }

    var resolvedRange: ClosedRange<Double>? {
        guard let loaded = editor.loaded else { return nil }
        return ProjectCompiler.exportRange(finalSettings.range, in: loaded, duration: editor.duration)
    }

    func start() {
        if rangeMode == "eachLap" { return startEachLap() }
        let settings = finalSettings
        let base = editor.fileURL?.deletingPathExtension().lastPathComponent ?? "Onboard Studio Export"
        guard
            let destination = OpenPanels.chooseExportDestination(
                suggestedName: base + "." + settings.fileExtension, fileExtension: settings.fileExtension)
        else { return }
        guard let loaded = editor.loaded else {
            failure = "The project has not finished loading."
            return
        }
        if rangeMode != "whole", resolvedRange == nil {
            failure = "The selected range is empty."
            return
        }
        failure = nil
        finishedURL = nil
        progress = ExportProgress(fraction: 0, framesWritten: 0, currentTime: 0)
        editor.edit("Change Export Settings") { $0.export = settings }
        let range = resolvedRange
        exportTask = Task {
            do {
                let compiled = ProjectCompiler.prepareForExport(
                    try await ProjectCompiler.compile(loaded), settings: settings)
                // The exporter reports every frame written; the sheet redraws only when it shows (#279).
                var throttle = ProgressThrottle()
                for try await update in Exporter.export(compiled, settings: settings, range: range, to: destination)
                where throttle.shouldReport(update.fraction) {
                    progress = update
                }
                finishedURL = destination
            } catch is CancellationError {
                failure = "Export cancelled."
                progress = nil
            } catch {
                failure = "\(error)"
                progress = nil
            }
            exportTask = nil
        }
    }
}

// MARK: - Every lap (#150)

extension ExportSheet {
    /// The laps the current options keep, as the files they will become.
    var lapExports: [LapExport] {
        guard let loaded = editor.loaded else { return [] }
        return ProjectCompiler.lapExports(finalSettings.range, in: loaded, duration: editor.duration)
    }

    @ViewBuilder var eachLapOptions: some View {
        Toggle("Complete laps only", isOn: $completeLapsOnly)
            .accessibilityIdentifier("export.completeLapsOnly")
            .help("Leave out the out-lap and the in-lap, which do not start or end at the line")
        Toggle("Skip slow laps", isOn: $skipSlowLaps)
            .accessibilityIdentifier("export.skipSlowLaps")
            .help("Leave out cool-down and traffic laps: those slower than the best lap by more than this")
        if skipSlowLaps {
            Stepper("Slower than the best by more than \(slowLapPercent) %", value: $slowLapPercent, in: 1...50)
        }
        let laps = lapExports
        Text(
            laps.isEmpty
                ? "No laps match; nothing would be written."
                : "Writes \(laps.count) \(laps.count == 1 ? "file" : "files"): "
                    + laps.map { "Lap \($0.lap)" }.joined(separator: ", ") + "."
        )
        .font(.caption).foregroundStyle(.secondary)
        .accessibilityIdentifier("export.lapFiles")
    }

    /// Writes one file per kept lap into a folder the user chooses, one after another, under one
    /// progress bar.
    func startEachLap() {
        let settings = finalSettings
        let laps = lapExports
        guard let loaded = editor.loaded else {
            failure = "The project has not finished loading."
            return
        }
        guard !laps.isEmpty else {
            failure = "No laps match, so there is nothing to export."
            return
        }
        guard let folder = OpenPanels.chooseExportFolder() else { return }
        let base = editor.fileURL?.deletingPathExtension().lastPathComponent ?? "Onboard Studio Export"
        failure = nil
        finishedURL = nil
        progress = ExportProgress(fraction: 0, framesWritten: 0, currentTime: 0)
        editor.edit("Change Export Settings") { $0.export = settings }
        exportTask = Task {
            do {
                let compiled = ProjectCompiler.prepareForExport(
                    try await ProjectCompiler.compile(loaded), settings: settings)
                var throttle = ProgressThrottle()
                for (index, lap) in laps.enumerated() {
                    batchLabel = "Exporting Lap \(lap.lap) — \(index + 1) of \(laps.count)"
                    let url = folder.appending(path: lap.fileName(base: base, fileExtension: settings.fileExtension))
                    for try await update in Exporter.export(compiled, settings: settings, range: lap.range, to: url) {
                        let overall = (Double(index) + update.fraction) / Double(laps.count)
                        guard throttle.shouldReport(overall) else { continue }
                        progress = ExportProgress(
                            fraction: overall, framesWritten: update.framesWritten, currentTime: update.currentTime)
                    }
                }
                batchLabel = nil
                finishedURL = folder
                let count = laps.count == 1 ? "1 lap" : "\(laps.count) laps"
                editor.statusMessage = "Exported \(count) to \(folder.lastPathComponent)."
            } catch is CancellationError {
                failure = "Export cancelled. The laps already written are kept."
                progress = nil
                batchLabel = nil
            } catch {
                failure = "\(error)"
                progress = nil
                batchLabel = nil
            }
            exportTask = nil
        }
    }
}
