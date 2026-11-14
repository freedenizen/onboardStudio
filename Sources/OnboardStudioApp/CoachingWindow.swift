import MediaKit
import ProjectModel
import SwiftUI
import TelemetryKit

struct CoachingContent: View {
    let source: any CoachingSource

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
    /// The walkthrough or every corner, as the driver last left it (#458); under the UI tests, in
    /// a store emptied at launch, so every test opens on the walkthrough.
    @AppStorage("coaching.mode", store: UITestSupport.paneDefaults) private var mode = CoachingMode.walkthrough

    /// The app's units; a project saved before the region decided *Automatic* (#464) keeps the
    /// metric notes its video is rendered with, so the window and the picture agree.
    var units: CoachingUnits {
        .following(
            SpeedUnitSetting(rawValue: appSpeedUnit) ?? .automatic,
            legacyAutomatic: source.editor?.project.settings.legacyAutomaticUnits ?? false)
    }

    var body: some View {
        Group {
            if let input = source.input {
                if let session = source.session {
                    content(input: input, session: session)
                } else if let problem = source.problem {
                    ContentUnavailableView(
                        "The Data File Did Not Load", systemImage: "exclamationmark.triangle",
                        description: Text(problem))
                } else {
                    ProgressView("Reading the data…").frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                ContentUnavailableView {
                    Label("No Data File", systemImage: "waveform.path.ecg")
                } description: {
                    Text("Coaching reads the laps of a data file: add one from your logger or phone app.")
                } actions: {
                    if let editor = source.editor {
                        Button("Add Data File…") { editor.addData() }.accessibilityIdentifier("coaching.addData")
                    }
                }
            }
        }
        .task(id: source.id) { await source.load() }
    }

    // MARK: - What is being read

    private func completeLaps(of session: TelemetrySession) -> [Lap] {
        LapDeltas.demotingShortLaps(session.laps, distance: session[.distance])
            .filter { $0.isComplete && $0.end != nil }
    }

    /// The lap to read without a choice: the lap at the playhead when it is a complete lap and
    /// not the reference, else the quickest lap that is not the reference, preferring one with no
    /// traffic mark (#571).
    private func defaultLap(in laps: [Lap], input: Input, reference: CoachingSettings.Reference) -> Lap? {
        let excluded: Int?
        switch reference {
        case .sessionBest: excluded = laps.min { ($0.duration ?? .infinity) < ($1.duration ?? .infinity) }?.number
        case .lap(let number): excluded = number
        case .fastestRolling, .compositeOptimal, .otherInput, .logbook: excluded = nil
        }
        // The lap at the playhead, when there is one: a logbook session has none.
        if let editor = source.editor,
            let atPlayhead = laps.first(where: {
                $0.contains(input.sync.inputTime(forProjectTime: editor.currentTime))
            }), atPlayhead.number != excluded
        {
            return atPlayhead
        }
        return source.session.flatMap { laps.quickest(excluding: excluded, in: $0) }
            ?? laps.sorted { ($0.duration ?? .infinity) < ($1.duration ?? .infinity) }.first { $0.number != excluded }
    }

    private func selection(input: Input, session: TelemetrySession) -> CoachingSelection? {
        let laps = completeLaps(of: session)
        let saved = source.settings
        let reference = saved?.reference ?? .sessionBest
        let lap =
            saved?.lap.flatMap { number in laps.first { $0.number == number } }
            ?? defaultLap(in: laps, input: input, reference: reference)
        guard let lap else { return nil }
        let stamp = session.laps.count &* 31 &+ Int(session.duration * 10)
        return CoachingSelection(
            input: input, lapNumber: lap.number, reference: reference, alignByPosition: saved?.alignByPosition ?? false,
            sessionStamp: stamp, traffic: saved?.traffic(for: input.id) ?? [],
            dismissedTraffic: saved?.dismissedTraffic(for: input.id) ?? [])
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
            Group {
                if mode == .walkthrough {
                    walkthrough(selection: selection, laps: laps)
                } else {
                    allCorners(selection: selection, laps: laps, input: input, session: session)
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
                laps.noun,
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
                    // A run's course ends at the finish: there is no rolling lap to offer (#552).
                    if !laps.areRuns {
                        Text(CoachingReference.fastestRolling.displayName)
                            .tag(CoachingSettings.Reference.fastestRolling)
                    }
                    Text(CoachingReference.compositeOptimal.displayName)
                        .tag(CoachingSettings.Reference.compositeOptimal)
                    ForEach(laps.filter { $0.number != selection.lapNumber }, id: \.number) { lap in
                        Text(Self.lapTitle(lap)).tag(CoachingSettings.Reference.lap(lap.number))
                    }
                }
                if let editor = source.editor {
                    ForEach(editor.project.dataInputs.filter { $0.id != selection.input.id }) { other in
                        if let session = editor.sessions[other.id] {
                            Section(other.label) {
                                ForEach(completeLaps(of: session), id: \.number) { lap in
                                    Text(Self.lapTitle(lap))
                                        .tag(
                                            CoachingSettings.Reference.otherInput(
                                                dataInputID: other.id, lap: lap.number))
                                }
                            }
                        }
                    }
                }
                logbookChoices(selection: selection)
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
            .disabled(Self.isAlwaysByPosition(selection.reference))
            .accessibilityIdentifier("coaching.alignByPosition")
            Spacer()
            if isAnalysing { ProgressView().controlSize(.small) }
        }
        .padding()
    }

    /// The laps a reference profile was cut from: one for a lap, several for a splice.
    static func lapNumbers(in reference: LapProfile) -> [Int] { reference.pieces.map(\.lapNumber) }

    static func lapTitle(_ lap: Lap) -> String {
        "\(lap.title) — \(TimeParsing.lapTimeString(lap.duration ?? 0, decimals: 2))"
    }
}

/// The window's two faces, and the parts of All Corners (#458).
extension CoachingContent {
    /// The guided debrief: one step at a time, a fresh one for each lap and reference (#458).
    @ViewBuilder
    private func walkthrough(selection: CoachingSelection, laps: [Lap]) -> some View {
        if let analysis, analysed == selection {
            CoachingWalkthroughView(
                analysis: analysis, lapNumber: selection.lapNumber, units: units, others: otherProfiles, source: source,
                watch: { [source] comparison in
                    await source.watchClips(for: comparison, analysis: analysis, selection: selection)
                },
                markTraffic: { setTraffic($1, corner: $0.index, analysis: analysis, selection: selection) },
                answerSuggestion: { answer($0, isTraffic: $1, analysis: analysis, selection: selection) },
                change: { choices(selection: selection, laps: laps) }
            )
            .id(selection)
        } else if isAnalysing {
            ProgressView("Reading the laps…").frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: 0) {
                choices(selection: selection, laps: laps)
                Divider()
                ContentUnavailableView(
                    "Nothing to Compare", systemImage: "flag.checkered",
                    description: Text(
                        "This lap could not be read against \(referenceName(selection.reference)). The optimal lap "
                            + "needs every sector timed once; a lap from another file needs that file to have loaded."))
            }
        }
    }

    /// Every corner at once: the cards, the plan, the table and a corner's detail.
    @ViewBuilder
    private func allCorners(
        selection: CoachingSelection, laps: [Lap], input: Input, session: TelemetrySession
    ) -> some View {
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
                        for: comparison, analysis: analysis, selection: selection, session: session),
                    lapNumber: selection.lapNumber,
                    markTraffic: { setTraffic($0, corner: comparison.index, analysis: analysis, selection: selection) },
                    answerSuggestion: { answer($0, isTraffic: $1, analysis: analysis, selection: selection) }
                )
                .frame(minWidth: 300, idealWidth: 340, maxWidth: 440)
            }
        }
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
                Group {
                    if let editor = source.editor {
                        NextSessionPlanView(
                            editor: editor, input: input, analysis: analysis, lapNumber: selection.lapNumber)
                    } else {
                        makeProject
                    }
                }
                .padding(.horizontal)
                .focusedSceneValue(\.coachingSheet, sheetAction(analysis, selection: selection, session: session))
                CornerTable(
                    rows: analysis.rows(units: units), selection: $selectedCorner, sortOrder: $sortOrder, units: units,
                    mark: { setTraffic($1, corner: $0, analysis: analysis, selection: selection) },
                    dismissSuggestion: { answer($0, isTraffic: false, analysis: analysis, selection: selection) })
                if !analysis.warnings.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(analysis.warnings.map(describe), id: \.self) { line in
                            Label(line, systemImage: "info.circle").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .padding([.horizontal, .bottom])
                }
                if source.editor == nil, let message = source.message {
                    Text(message).font(.callout).foregroundStyle(.secondary).padding([.horizontal, .bottom])
                        .accessibilityIdentifier("coaching.message")
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
}

extension CoachingContent {
    // MARK: - Doing

    func analyse(_ selection: CoachingSelection, session read: TelemetrySession) async {
        // The marks as chosen, not as the last compile left them on the session.
        let session = {
            var session = read
            session.traffic = selection.traffic
            session.dismissedTraffic = selection.dismissedTraffic
            return session
        }()
        isAnalysing = true
        defer { isAnalysing = false }
        guard let lap = session.laps.first(where: { $0.number == selection.lapNumber }) else {
            analysis = nil
            analysed = selection
            return
        }
        let units = units
        var other: OtherReference?
        if case .otherInput(let id, let number) = selection.reference, let editor = source.editor,
            let session = editor.sessions[id], let input = editor.project.input(id)
        {
            other = OtherReference(session: session, label: input.label, lap: number)
        } else if case .logbook(let entryID, let number) = selection.reference,
            let entry = LogbookModel.shared.entries.first(where: { $0.id == entryID })
        {
            // Read in on demand, once; a session the logbook has lost reads as nothing to compare.
            if let loaded = await LogbookModel.shared.session(for: entry) {
                let lap = number ?? entry.bestLapNumber ?? LapDeltas.sessionBest(in: loaded)?.number ?? 0
                let label = LogbookReferences.phrase(for: entry, lap: nil).replacingOccurrences(
                    of: ", lap \(lap)", with: "")
                other = OtherReference(session: loaded, label: label, lap: lap)
            }
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
            case .otherInput, .logbook: return nil
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
        // A logbook session has no picture in any project: nothing to compare (#396).
        guard let editor = source.editor else { return nil }
        let referenceSide: (input: InputID, lap: Int)?
        var splice: LapComparisonSettings.ComparedSplice?
        switch selection.reference {
        case .sessionBest: referenceSide = LapDeltas.sessionBest(in: session).map { (selection.input.id, $0.number) }
        case .lap(let number): referenceSide = (selection.input.id, number)
        case .otherInput(let id, let number): referenceSide = (id, number)
        case .logbook: return nil  // its video is not in the project; add the session as an input to compare pictures
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
        return { editor.compareLaps(settings, range: end > start ? max(0, start)...end : nil) }
    }

    /// Moves the playhead to `distance` metres into the lap being read.
    func seek(to distance: Double, in analysis: CoachingAnalysis, input: Input) {
        guard let editor = source.editor else { return }
        let dataTime = analysis.lap.time(atDistance: distance)
        editor.seek(to: max(0, input.sync.projectTime(forInputTime: dataTime)))
    }
}
