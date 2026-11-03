import ProjectModel
import SwiftUI
import TelemetryKit

/// Where the time went (#321): one lap of the front project's data read against a reference —
/// the best lap, the fastest rolling lap, the optimal lap spliced from the best sectors, another
/// lap, or a lap of another data file — as the top opportunities with what to try, and every
/// corner in a table. Selecting a corner, or Show Me, moves the playhead there.
///
/// A window beside the document rather than an inspector section: a corner table needs width,
/// and the inspector is a column. It follows the front document the way the attribute window
/// does, through `ActiveEditor`.
struct CoachingWindow: View {
    static let windowID = "coaching"

    private var active = ActiveEditor.shared

    static func open(_ openWindow: OpenWindowAction) { openWindow(id: windowID) }

    var body: some View {
        Group {
            if let editor = active.editor {
                CoachingContent(editor: editor)
                    // The menu bar reaches this document from here too: Edit ▸ Undo names and takes
                    // back the last edit, and the Project menu's items apply to it.
                    .focusedSceneValue(\.editor, editor)
                    .background(DocumentWindowTag())
            } else {
                ContentUnavailableView(
                    "No Project Open", systemImage: "flag.checkered",
                    description: Text(
                        "Open a project with a data file, then choose Project ▸ Coaching… to see where its laps "
                            + "lost time."))
            }
        }
        .frame(minWidth: 880, minHeight: 480)
    }
}

/// What the window reads for the front document: which input, lap and reference, resolved from
/// the project's coaching settings with the defaults filled in.
struct CoachingSelection: Hashable, Sendable {
    var input: Input
    var lapNumber: Int
    var reference: CoachingSettings.Reference
    var alignByPosition: Bool
    /// A cheap fingerprint of the session, so a re-import re-reads the analysis.
    var sessionStamp: Int

    var settings: CoachingSettings {
        CoachingSettings(
            dataInputID: input.id, lap: lapNumber, reference: reference, alignByPosition: alignByPosition)
    }

    /// The analysis options the choices amount to.
    var options: CoachingOptions {
        var options = CoachingOptions()
        if alignByPosition { options.alignment = .byPosition }
        return options
    }
}

struct CoachingContent: View {
    let editor: EditorModel

    @AppStorage(Preferences.speedUnit.key) private var appSpeedUnit = Preferences.speedUnit.unset
    @State private var analysis: CoachingAnalysis?
    /// Every other complete lap of the session, read with the analysis, for the corner detail's
    /// spread of lines (#334).
    @State private var otherProfiles: [LapProfile] = []
    @State private var analysed: CoachingSelection?
    @State private var isAnalysing = false
    @State private var selectedCorner: Int?
    /// Set while Show Me selects a corner, so the selection handler does not move the playhead
    /// from the brake point Show Me chose to the turn-in it would choose.
    @State private var selectingForShowMe = false
    @State private var sortOrder = [KeyPathComparator(\CornerRow.timeLost, order: .reverse)]

    var units: CoachingUnits { appSpeedUnit == SpeedUnitSetting.mph.rawValue ? .imperial : .metric }

    var body: some View {
        if let input = currentInput {
            if let session = editor.sessions[input.id] {
                content(input: input, session: session)
            } else if let problem = editor.problems[input.id] {
                ContentUnavailableView(
                    "The Data File Did Not Load", systemImage: "exclamationmark.triangle", description: Text(problem))
            } else {
                ProgressView("Reading the data…").frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        } else {
            ContentUnavailableView {
                Label("No Data File", systemImage: "waveform.path.ecg")
            } description: {
                Text("Coaching reads the laps of a data file: add one from your logger or phone app.")
            } actions: {
                Button("Add Data File…") { editor.addData() }.accessibilityIdentifier("coaching.addData")
            }
        }
    }

    // MARK: - What is being read

    private var currentInput: Input? {
        if let id = editor.project.coaching?.dataInputID,
            let input = editor.project.dataInputs.first(where: { $0.id == id })
        {
            return input
        }
        return editor.lapInput
    }

    private func completeLaps(of session: TelemetrySession) -> [Lap] {
        LapDeltas.demotingShortLaps(session.laps, distance: session[.distance])
            .filter { $0.isComplete && $0.end != nil }
    }

    /// The lap to read without a choice: the lap at the playhead when it is a complete lap and
    /// not the reference, else the quickest lap that is not the reference.
    private func defaultLap(in laps: [Lap], input: Input, reference: CoachingSettings.Reference) -> Lap? {
        let excluded: Int?
        switch reference {
        case .sessionBest: excluded = laps.min { ($0.duration ?? .infinity) < ($1.duration ?? .infinity) }?.number
        case .lap(let number): excluded = number
        case .fastestRolling, .compositeOptimal, .otherInput: excluded = nil
        }
        let dataTime = input.sync.inputTime(forProjectTime: editor.currentTime)
        if let atPlayhead = laps.first(where: { $0.contains(dataTime) }), atPlayhead.number != excluded {
            return atPlayhead
        }
        return laps.sorted { ($0.duration ?? .infinity) < ($1.duration ?? .infinity) }.first { $0.number != excluded }
    }

    private func selection(input: Input, session: TelemetrySession) -> CoachingSelection? {
        let laps = completeLaps(of: session)
        let saved = editor.project.coaching
        let reference = saved?.reference ?? .sessionBest
        let lap =
            saved?.lap.flatMap { number in laps.first { $0.number == number } }
            ?? defaultLap(in: laps, input: input, reference: reference)
        guard let lap else { return nil }
        let stamp = session.laps.count &* 31 &+ Int(session.duration * 10)
        return CoachingSelection(
            input: input, lapNumber: lap.number, reference: reference, alignByPosition: saved?.alignByPosition ?? false,
            sessionStamp: stamp)
    }

    private func setLap(_ number: Int, selection: CoachingSelection) {
        var settings = selection.settings
        settings.lap = number
        editor.edit("Change Coaching Lap") { $0.coaching = settings }
    }

    private func setReference(_ reference: CoachingSettings.Reference, selection: CoachingSelection) {
        var settings = selection.settings
        settings.reference = reference
        editor.edit("Change Coaching Reference") { $0.coaching = settings }
    }

    private func setAlignByPosition(_ byPosition: Bool, selection: CoachingSelection) {
        var settings = selection.settings
        settings.alignByPosition = byPosition
        editor.edit("Change Coaching Alignment") { $0.coaching = settings }
    }

    // MARK: - Layout

    @ViewBuilder
    private func content(input: Input, session: TelemetrySession) -> some View {
        let laps = completeLaps(of: session)
        if laps.isEmpty {
            ContentUnavailableView(
                "No Complete Laps", systemImage: "flag.checkered",
                description: Text(
                    "Coaching compares complete laps. Set a start/finish line in the data file's inspector, or check "
                        + "that the file has position and distance."))
        } else if let selection = selection(input: input, session: session) {
            HSplitView {
                VStack(spacing: 0) {
                    choices(selection: selection, laps: laps)
                    Divider()
                    results(selection: selection, input: input, session: session)
                }
                .frame(minWidth: 560)
                .layoutPriority(1)
                if let analysis, analysed == selection, let corner = selectedCorner,
                    let comparison = analysis.corners.first(where: { $0.index == corner })
                {
                    CornerDetailView(
                        analysis: analysis, comparison: comparison, units: units, others: otherProfiles,
                        compareInVideo: compareAction(
                            for: comparison, analysis: analysis, selection: selection, session: session)
                    )
                    .frame(minWidth: 300, idealWidth: 340, maxWidth: 440)
                }
            }
            .task(id: selection) { await analyse(selection, session: session) }
            .onChange(of: selectedCorner) { _, corner in
                guard !selectingForShowMe else {
                    selectingForShowMe = false
                    return
                }
                guard let corner, let analysis, let comparison = analysis.corners.first(where: { $0.index == corner })
                else { return }
                seek(to: comparison.lap.corner.startDistance, in: analysis, input: input)
            }
        }
    }

    private func choices(selection: CoachingSelection, laps: [Lap]) -> some View {
        HStack(spacing: 16) {
            Picker(
                "Lap",
                selection: Binding(
                    get: { selection.lapNumber }, set: { setLap($0, selection: selection) })
            ) {
                ForEach(laps, id: \.number) { lap in
                    Text(Self.lapTitle(lap)).tag(lap.number)
                }
            }
            .accessibilityIdentifier("coaching.lap")
            Picker(
                "Compared with",
                selection: Binding(
                    get: { selection.reference }, set: { setReference($0, selection: selection) })
            ) {
                Section("This session") {
                    Text(CoachingReference.sessionBest.displayName).tag(CoachingSettings.Reference.sessionBest)
                    Text(CoachingReference.fastestRolling.displayName).tag(CoachingSettings.Reference.fastestRolling)
                    Text(CoachingReference.compositeOptimal.displayName)
                        .tag(CoachingSettings.Reference.compositeOptimal)
                    ForEach(laps.filter { $0.number != selection.lapNumber }, id: \.number) { lap in
                        Text(Self.lapTitle(lap)).tag(CoachingSettings.Reference.lap(lap.number))
                    }
                }
                ForEach(editor.project.dataInputs.filter { $0.id != selection.input.id }) { other in
                    if let session = editor.sessions[other.id] {
                        Section(other.label) {
                            ForEach(completeLaps(of: session), id: \.number) { lap in
                                Text(Self.lapTitle(lap))
                                    .tag(CoachingSettings.Reference.otherInput(dataInputID: other.id, lap: lap.number))
                            }
                        }
                    }
                }
            }
            .accessibilityIdentifier("coaching.reference")
            Toggle(
                "Line up by position",
                isOn: Binding(
                    get: { selection.alignByPosition }, set: { setAlignByPosition($0, selection: selection) })
            )
            .help(
                "Match the two laps by where the car was rather than metre for metre: for two laps of one session "
                    + "driven on different lines. A lap from another file is always matched by position."
            )
            .disabled({ if case .otherInput = selection.reference { true } else { false } }())
            .accessibilityIdentifier("coaching.alignByPosition")
            Spacer()
            if isAnalysing { ProgressView().controlSize(.small) }
        }
        .padding()
    }

    @ViewBuilder
    private func results(selection: CoachingSelection, input: Input, session: TelemetrySession) -> some View {
        if let analysis, analysed == selection {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(analysis.headline(lapNumber: selection.lapNumber, units: units))
                        .font(.headline)
                        .accessibilityIdentifier("coaching.headline")
                    Text([analysis.splicedFrom, analysis.alignmentLine].compactMap { $0 }.joined(separator: ". "))
                        .font(.caption).foregroundStyle(.secondary)
                        .accessibilityIdentifier("coaching.alignment")
                }
                .padding(.horizontal)
                .padding(.top, 12)
                opportunities(analysis, input: input)
                NextSessionPlanView(editor: editor, input: input, analysis: analysis, lapNumber: selection.lapNumber)
                    .padding(.horizontal)
                    .focusedSceneValue(\.coachingSheet, sheet(analysis, selection: selection, session: session))
                CornerTable(
                    rows: analysis.rows(units: units), selection: $selectedCorner, sortOrder: $sortOrder, units: units)
                if !analysis.warnings.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(analysis.warnings.map(describe), id: \.self) { line in
                            Label(line, systemImage: "info.circle").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .padding([.horizontal, .bottom])
                }
            }
        } else if isAnalysing {
            ProgressView("Reading the laps…").frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ContentUnavailableView(
                "Nothing to Compare", systemImage: "flag.checkered",
                description: Text(
                    "This lap could not be read against \(referenceName(selection.reference)). The optimal lap needs "
                        + "every sector timed once; a lap from another file needs that file to have loaded."))
        }
    }

    private func opportunities(_ analysis: CoachingAnalysis, input: Input) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Opportunities").font(.subheadline.weight(.semibold)).padding(.horizontal)
            if analysis.top.isEmpty {
                Text("Nothing lost against \(analysis.referencePhrase).")
                    .foregroundStyle(.secondary).padding(.horizontal)
            } else {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(analysis.top) { opportunity in
                        OpportunityCard(opportunity: opportunity) {
                            if selectedCorner != opportunity.corner.index {
                                selectingForShowMe = true
                                selectedCorner = opportunity.corner.index
                            }
                            seek(to: opportunity.corner.lap.phaseStart, in: analysis, input: input)
                        }
                    }
                }
                .padding(.horizontal)
            }
        }
    }

    /// The laps a reference profile was cut from: one for a lap, several for a splice.
    static func lapNumbers(in reference: LapProfile) -> [Int] { reference.pieces.map(\.lapNumber) }

    static func lapTitle(_ lap: Lap) -> String {
        "Lap \(lap.number) — \(TimeParsing.lapTimeString(lap.duration ?? 0, decimals: 2))"
    }
}

/// A lap of another data file, as a reference.
struct OtherReference: Sendable {
    let session: TelemetrySession
    let label: String
    let lap: Int
}

extension CoachingContent {
    // MARK: - Doing

    func analyse(_ selection: CoachingSelection, session: TelemetrySession) async {
        isAnalysing = true
        defer { isAnalysing = false }
        guard let lap = session.laps.first(where: { $0.number == selection.lapNumber }) else {
            analysis = nil
            analysed = selection
            return
        }
        let units = units
        let other: OtherReference?
        if case .otherInput(let id, let number) = selection.reference, let session = editor.sessions[id],
            let input = editor.project.input(id)
        {
            other = OtherReference(session: session, label: input.label, lap: number)
        } else {
            other = nil
        }
        let reference = selection.reference
        let options = selection.options
        let result = await Task.detached(priority: .userInitiated) { () -> CoachingAnalysis? in
            if let other {
                guard let lapProfile = LapProfile(lap: lap, in: session),
                    let otherLap = other.session.laps.first(where: { $0.number == other.lap }),
                    let referenceProfile = LapProfile(lap: otherLap, in: other.session)
                else { return nil }
                return CoachingAnalysis.analyse(
                    lap: lapProfile, in: session, reference: referenceProfile,
                    referencePhrase: "\(other.label) lap \(other.lap)", sameSession: false, units: units,
                    options: options)
            }
            let same: CoachingReference
            switch reference {
            case .sessionBest: same = .sessionBest
            case .lap(let number): same = .lap(number)
            case .fastestRolling: same = .fastestRolling
            case .compositeOptimal: same = .compositeOptimal
            case .otherInput: return nil
            }
            return CoachingAnalysis.analyse(lap: lap, reference: same, in: session, units: units, options: options)
        }.value
        guard !Task.isCancelled else { return }
        analysis = result
        analysed = selection
        let excluded = [selection.lapNumber] + (result.map { Self.lapNumbers(in: $0.reference) } ?? [])
        let laps = completeLaps(of: session).filter { !excluded.contains($0.number) }
        otherProfiles = await Task.detached(priority: .utility) {
            laps.compactMap { LapProfile(lap: $0, in: session) }
        }.value
    }

    /// Compare Laps over this corner, when the reference is a real lap with a camera; `nil` for
    /// a rolling or spliced lap, which has no single picture.
    func compareAction(
        for comparison: CornerComparison, analysis: CoachingAnalysis, selection: CoachingSelection,
        session: TelemetrySession
    ) -> (() -> Void)? {
        let referenceSide: (input: InputID, lap: Int)?
        var splice: LapComparisonSettings.ComparedSplice?
        switch selection.reference {
        case .sessionBest: referenceSide = LapDeltas.sessionBest(in: session).map { (selection.input.id, $0.number) }
        case .lap(let number): referenceSide = (selection.input.id, number)
        case .otherInput(let id, let number): referenceSide = (id, number)
        case .fastestRolling:
            // A spliced lap's picture is cut from the laps it came from (#328).
            referenceSide = (selection.input.id, selection.lapNumber)
            splice = .fastestRolling
        case .compositeOptimal:
            referenceSide = (selection.input.id, selection.lapNumber)
            splice = .compositeOptimal
        }
        guard let side = referenceSide,
            splice != nil || side.lap != selection.lapNumber || side.input != selection.input.id,
            let camera = editor.camera(for: selection.input.id), let referenceCamera = editor.camera(for: side.input)
        else { return nil }
        let settings = LapComparisonSettings(
            lap: .init(dataInputID: selection.input.id, videoInputID: camera, lap: selection.lapNumber),
            comparedLap: .init(dataInputID: side.input, videoInputID: referenceCamera, lap: side.lap),
            layout: .sideBySide, comparedSplice: splice)
        let input = selection.input
        let start = input.sync.projectTime(forInputTime: analysis.lap.time(atDistance: comparison.lap.phaseStart))
        let endDistance = min(analysis.lap.lengthMeters, comparison.lap.corner.endDistance + 100)
        let end = input.sync.projectTime(forInputTime: analysis.lap.time(atDistance: endDistance))
        let editor = editor
        return { editor.compareLaps(settings, range: end > start ? max(0, start)...end : nil) }
    }

    /// Moves the playhead to `distance` metres into the lap being read.
    func seek(to distance: Double, in analysis: CoachingAnalysis, input: Input) {
        let dataTime = analysis.lap.time(atDistance: distance)
        editor.seek(to: max(0, input.sync.projectTime(forInputTime: dataTime)))
    }

}
