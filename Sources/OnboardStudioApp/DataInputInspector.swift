import ProjectModel
import SwiftUI
import TelemetryKit

/// Data-input sections: channel mapping, processing, calculated fields and lap detection.
struct DataInputInspector: View {
    @Bindable var editor: EditorModel
    let input: Input
    let settings: DataInputSettings

    // Not private: the Track and Corners sections live in `DataInputTrackInspector.swift`.
    @State var circuitSearch = ""
    @State var showCorners = false
    /// Room for a corner name such as `3a` or `Carousel`, growing with the text size.
    @ScaledMetric(relativeTo: .body) var cornerNameWidth: CGFloat = 70

    var session: TelemetrySession? { editor.sessions[input.id] }

    var body: some View {
        // One way in (#215): what the attributes are mapped to, how the import went, and the
        // window that does both. The per-column list and a second button to the same window used
        // to sit alongside, each a partial view of the same thing.
        DataInputAttributesSection(editor: editor, input: input, settings: settings, session: session)
        Section("Processing") {
            Toggle(
                "Derive speed from GPS when missing",
                isOn: field(\.deriveSpeedFromPosition, name: "Toggle Speed Derivation"))
            Toggle(
                "Derive heading from GPS when missing",
                isOn: field(\.deriveHeadingFromPosition, name: "Toggle Heading Derivation"))
            Picker(
                "Resample",
                selection: Binding(
                    get: { settings.resampleHertz ?? 0 },
                    set: { v in update("Change Resampling") { $0.resampleHertz = v > 0 ? v : nil } })
            ) {
                Text("As recorded").tag(0.0)
                Text("10 Hz").tag(10.0)
                Text("25 Hz").tag(25.0)
                Text("50 Hz").tag(50.0)
            }
            SliderField(
                "Smoothing", value: field(\.smoothingSeconds, name: "Change Smoothing"), in: 0...3, step: 0.1,
                scale: .plain(fractionDigits: 1), unit: "s"
            )
            .help("How long a change takes to show, in seconds; 0 turns smoothing off")
        }
        Section("Trim") {
            // In the file's own seconds, like a video's trim. Applied before laps are detected,
            // so trimming an out-lap away stops it counting rather than renumbering it.
            OptionalNumberField(
                "Start", value: field(\.trim.start, name: "Trim Data Start"),
                placeholder: "from the beginning"
            )
            .accessibilityIdentifier("data.trimStart")
            OptionalNumberField(
                "End", value: field(\.trim.end, name: "Trim Data End"), placeholder: "to the end"
            )
            .accessibilityIdentifier("data.trimEnd")
            Text("Seconds into the data file. Laps, deltas and calculated fields are worked out from what is left.")
                .font(.caption).foregroundStyle(.secondary)
        }
        Section("Calculated Fields") {
            ForEach(Array(settings.calculatedFields.enumerated()), id: \.offset) { index, spec in
                CalculatedFieldRow(spec: spec, valid: (try? Expression(spec.expression)) != nil) { newSpec in
                    update("Edit Calculated Field") { $0.calculatedFields[index] = newSpec }
                } remove: {
                    update("Remove Calculated Field") { $0.calculatedFields.remove(at: index) }
                }
            }
            Button("Add Calculated Field") {
                update("Add Calculated Field") {
                    $0.calculatedFields.append(
                        CalculatedFieldSpec(
                            name: "field\($0.calculatedFields.count + 1)", expression: "speed * 3.6", unit: "km/h"))
                }
            }
            Text(
                "Channels by identifier (speed, rpm, obd:Coolant, [aux:Oil temp]); + − × ÷, comparisons, "
                    + "if(cond, a, b), min, max, abs, clamp."
            )
            .font(.caption).foregroundStyle(.secondary)
        }
        trackSection
        Section("Laps") {
            Toggle(
                "Detect laps from a start/finish line",
                isOn: Binding(
                    get: { settings.lapLine != nil },
                    set: { on in
                        update(on ? "Enable Lap Detection" : "Use File Laps") {
                            $0.lapLine = on ? (currentPositionLine ?? LapLineSpec(latitude: 0, longitude: 0)) : nil
                        }
                    }))
            Button("Suggest a Start/Finish from the Data") { editor.suggestStartFinish(for: input.id) }
                .accessibilityIdentifier("data.suggestStartFinish")
                .disabled(session == nil)
            if let line = settings.lapLine {
                Toggle("Place it on the track map", isOn: placingOnMap)
                    .accessibilityIdentifier("data.placeStartFinish")
                Text(
                    "Drag the yellow line to move it, or either end to turn it. The stub shows which way the "
                        + "car crosses. Needs a track map object on screen."
                )
                .font(.caption).foregroundStyle(.secondary)
                Button("Use Current Preview Position as Start/Finish") {
                    if let here = currentPositionLine {
                        update("Set Start/Finish") {
                            $0.lapLine = LapLineSpec(
                                latitude: here.latitude, longitude: here.longitude, headingDegrees: here.headingDegrees,
                                halfWidthMeters: line.halfWidthMeters,
                                headingToleranceDegrees: line.headingToleranceDegrees,
                                ignoreFirstCrossings: line.ignoreFirstCrossings)
                        }
                    }
                }
                .disabled(currentPositionLine == nil)
                NumberField("Latitude", value: lineField(\.latitude), fractionDigits: 0...6, step: 0.0001)
                NumberField("Longitude", value: lineField(\.longitude), fractionDigits: 0...6, step: 0.0001)
                NumberField(
                    "Heading (°)",
                    value: Binding(
                        get: { line.headingDegrees ?? -1 },
                        set: { v in updateLine { $0.headingDegrees = v < 0 ? nil : v } }))
                NumberField("Line half-width (m)", value: lineField(\.halfWidthMeters))
                NumberField("Heading tolerance (°)", value: lineField(\.headingToleranceDegrees))
                Stepper(
                    "Ignore first crossings: \(line.ignoreFirstCrossings)",
                    value: Binding(
                        get: { line.ignoreFirstCrossings },
                        set: { v in updateLine { $0.ignoreFirstCrossings = max(0, v) } }), in: 0...10)
            }
            if let session, !session.laps.isEmpty {
                ForEach(session.laps, id: \.number) { lap in
                    LabeledContent("Lap \(lap.number)") {
                        Text(lap.duration.map(TimeParsing.lapTimeString) ?? "—").monospacedDigit()
                            .foregroundStyle(lap.isComplete ? .primary : .secondary)
                    }
                }
            } else {
                Text("No laps found.").foregroundStyle(.secondary)
            }
        }
        sectorsSection
    }

    /// How this file's laps are split, and what the split produced. Nothing here knows the
    /// circuit: no source publishes sector geometry under a licence we can use, so the sectors
    /// are derived from the driving or placed by hand.
    @ViewBuilder var sectorsSection: some View {
        Section("Sectors") {
            Picker("Split each lap by", selection: sectorField(\.mode)) {
                ForEach(SectorSpec.Mode.allCases, id: \.self) { Text($0.displayName).tag($0) }
            }
            switch settings.sectors.mode {
            case .equalDistance, .cornerAware:
                Stepper(
                    "Sectors: \(settings.sectors.count)",
                    value: Binding(
                        get: { settings.sectors.count },
                        set: { v in updateSectors { $0.count = max(1, min(12, v)) } }), in: 1...12)
                Text(
                    settings.sectors.mode == .cornerAware
                        ? "Each boundary moves onto the nearest straight, so a sector never cuts a corner in half."
                        : "Equal parts of the fastest lap's distance. Works anywhere, including a venue nobody "
                            + "has mapped."
                )
                .font(.caption).foregroundStyle(.secondary)
            case .manual:
                Button("Add Gate at Preview Position") {
                    if let here = currentPositionLine { updateSectors { $0.lines.append(here) } }
                }
                .disabled(currentPositionLine == nil)
                ForEach(Array(settings.sectors.lines.enumerated()), id: \.offset) { index, line in
                    LabeledContent("Gate \(index + 1)") {
                        HStack {
                            Text(String(format: "%.5f, %.5f", line.latitude, line.longitude))
                                .monospacedDigit().foregroundStyle(.secondary)
                            Button("Remove") { updateSectors { $0.lines.remove(at: index) } }
                        }
                    }
                }
                Text("Gates are crossed in the order the track runs them; the start/finish line is not one of them.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let analysis = session?.sectors, analysis.count > 1 {
                let boundaries = analysis.layout.boundaryDistances.map { String(format: "%.0f m", $0) }
                LabeledContent("Boundaries") {
                    Text(boundaries.joined(separator: ", ")).foregroundStyle(.secondary)
                }
                ForEach(0..<analysis.count, id: \.self) { index in
                    LabeledContent(SectorLayout.name(of: index)) {
                        Text(
                            analysis.best[index].map {
                                TimeParsing.lapTimeString($0.time, decimals: 2) + "  (lap \($0.lapNumber))"
                            } ?? "—"
                        )
                        .monospacedDigit().foregroundStyle(.secondary)
                    }
                }
                if let theoretical = analysis.theoreticalLapTime {
                    LabeledContent("Theoretical lap") {
                        Text(TimeParsing.lapTimeString(theoretical, decimals: 2)).monospacedDigit()
                    }
                }
            } else {
                Text("Sectors need laps and a distance channel; a GPS file gets one.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    func sectorField<T>(_ keyPath: WritableKeyPath<SectorSpec, T>) -> Binding<T> {
        Binding(
            get: { settings.sectors[keyPath: keyPath] }, set: { v in updateSectors { $0[keyPath: keyPath] = v } })
    }

    func updateSectors(_ change: (inout SectorSpec) -> Void) {
        update("Edit Sectors") { change(&$0.sectors) }
    }

    /// Whether this input's line is the one being dragged about on the map. Turning it on turns it
    /// off everywhere else: two lines being placed at once would be two lines under one pointer.
    var placingOnMap: Binding<Bool> {
        Binding(
            get: { editor.startFinishEditing == input.id },
            set: { editor.startFinishEditing = $0 ? input.id : nil })
    }

    /// Position and heading at the current preview time, mapped through this input's sync.
    var currentPositionLine: LapLineSpec? {
        guard let session else { return nil }
        let inputTime = input.sync.inputTime(forProjectTime: editor.currentTime)
        guard let line = LapDetector.finishLine(at: inputTime, in: session) else { return nil }
        return LapLineSpec(latitude: line.latitude, longitude: line.longitude, headingDegrees: line.headingDegrees)
    }

    func field<T>(_ keyPath: WritableKeyPath<DataInputSettings, T>, name: String) -> Binding<T> {
        Binding(get: { settings[keyPath: keyPath] }, set: { value in update(name) { $0[keyPath: keyPath] = value } })
    }

    func lineField(_ keyPath: WritableKeyPath<LapLineSpec, Double>) -> Binding<Double> {
        Binding(
            get: { settings.lapLine?[keyPath: keyPath] ?? 0 }, set: { v in updateLine { $0[keyPath: keyPath] = v } })
    }

    func updateLine(_ change: (inout LapLineSpec) -> Void) {
        update("Edit Start/Finish") { settings in
            guard var line = settings.lapLine else { return }
            change(&line)
            settings.lapLine = line
        }
    }

    func update(_ name: String, _ change: (inout DataInputSettings) -> Void) {
        var new = settings
        change(&new)
        editor.updateInput(input.id, name: name) { $0.kind = .data(new) }
    }
}

struct CalculatedFieldRow: View {
    let spec: CalculatedFieldSpec
    let valid: Bool
    let change: (CalculatedFieldSpec) -> Void
    let remove: () -> Void

    // A name and a unit are short by nature; the expression below takes the full width. Scaled so
    // they still hold their text at larger sizes.
    @ScaledMetric(relativeTo: .body) private var nameWidth: CGFloat = 110
    @ScaledMetric(relativeTo: .body) private var unitWidth: CGFloat = 60

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                CommittingTextField(
                    "Name",
                    text: Binding(
                        get: { spec.name },
                        set: { v in
                            var s = spec
                            s.name = v
                            change(s)
                        })
                )
                .frame(width: nameWidth)
                CommittingTextField(
                    "Unit",
                    text: Binding(
                        get: { spec.unit },
                        set: { v in
                            var s = spec
                            s.unit = v
                            change(s)
                        })
                )
                .frame(width: unitWidth)
                Button(role: .destructive) {
                    remove()
                } label: {
                    Image(systemName: "minus.circle")
                }
                .buttonStyle(.borderless)
                .help("Remove this calculated field")
                .accessibilityLabel("Remove \(spec.name.isEmpty ? "calculated field" : spec.name)")
            }
            CommittingTextField(
                "Expression",
                text: Binding(
                    get: { spec.expression },
                    set: { v in
                        var s = spec
                        s.expression = v
                        change(s)
                    })
            )
            .font(.system(.body, design: .monospaced))
            .foregroundStyle(valid ? .primary : Color.red)
        }
    }
}
