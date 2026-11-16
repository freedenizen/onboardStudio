import ProjectModel
import SwiftUI
import TelemetryKit

/// Laps as data (#556): up to four laps over each other by the place on the track — delta-T against
/// the reference, speed, any channel the driver adds, the map and the friction circle — with one
/// cursor that every panel follows. The same view sits in the Analysis window, Coaching's Data tab
/// and the Logbook.
struct LapAnalysisView: View {
    @Bindable var model: LapAnalysisModel
    @AppStorage(Preferences.speedUnit.key) private var appSpeedUnit = Preferences.speedUnit.unset

    private var speedUnit: SpeedDisplayUnit {
        (SpeedUnitSetting(rawValue: appSpeedUnit) ?? .automatic).shown(in: .current)
    }
    private var metresPerUnit: Double { CoachingUnits.app.distance == .feet ? 0.3048 : 1 }
    private var distanceSymbol: String { CoachingUnits.app.distance == .feet ? "ft" : "m" }
    private var colors: [Color] { (0..<LapAnalysis.maximumLaps).map(LapAnalysisModel.color) }

    var body: some View {
        if !model.hasSource {
            ContentUnavailableView(
                "No Laps to Analyse", systemImage: "chart.xyaxis.line",
                description: Text(
                    "Select a session in the Logbook and choose Analyse Laps…, or open a project with laps and choose "
                        + "Window ▸ Analysis, to lay its laps over each other."))
        } else if let problem = model.problem {
            ContentUnavailableView(
                "The Session Did Not Load", systemImage: "exclamationmark.triangle", description: Text(problem))
        } else if model.isLoading {
            ProgressView("Reading the session…").frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            HSplitView {
                AnalysisLapList(model: model).frame(minWidth: 220, idealWidth: 250, maxWidth: 340)
                content.frame(minWidth: 620, minHeight: 420).layoutPriority(1)
            }
        }
    }

    @ViewBuilder private var content: some View {
        if let analysis = model.analysis {
            VStack(alignment: .leading, spacing: 8) {
                controls(analysis)
                AnalysisReadout(
                    analysis: analysis, cursor: model.cursor, colors: colors, speedUnit: speedUnit,
                    metresPerUnit: metresPerUnit, distanceSymbol: distanceSymbol)
                HStack(alignment: .top, spacing: 12) {
                    ScrollView { traces(analysis) }
                    if model.layout.showsMap || model.layout.showsFrictionCircle || showsPicture {
                        sidePanels(analysis)
                    }
                }
            }
            .padding(12)
        } else if model.isBuilding {
            ProgressView("Laying the laps over each other…").frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ContentUnavailableView(
                "Choose Laps", systemImage: "checklist",
                description: Text(
                    "Tick up to four laps in the list. The first is the reference the others are read against; a "
                        + "lap with no distance or position cannot be laid over the others."))
        }
    }

    private func controls(_ analysis: LapAnalysis) -> some View {
        HStack(spacing: 10) {
            Button("Whole Lap") { model.showWholeLap() }
                .disabled(model.visible == nil)
                .help("Show the whole lap in the traces")
                .accessibilityIdentifier("analysis.wholeLap")
            Menu("Go to Corner") {
                ForEach(analysis.corners, id: \.label) { corner in Button(corner.title) { model.zoom(to: corner) } }
            }
            .fixedSize()
            .disabled(analysis.corners.isEmpty)
            .help("Zoom the traces to a corner, from the braking into it to the drive out")
            .accessibilityIdentifier("analysis.corners")
            Spacer()
            AnalysisPanelsMenu(model: model)
        }
        .font(.callout)
    }

    @ViewBuilder private func traces(_ analysis: LapAnalysis) -> some View {
        let grid = analysis.grid(in: model.span)
        let layout = model.layout
        VStack(alignment: .leading, spacing: 10) {
            if layout.showsDelta {
                AnalysisTracePanel(
                    title: "Delta-T to \(analysis.reference.label) (s)",
                    series: series(analysis) { analysis.delta($0, at: grid) }, span: model.span,
                    height: layout.traceHeight, metresPerUnit: metresPerUnit, unitSymbol: "s", cursor: $model.cursor,
                    zeroLine: true, format: { String(format: "%+.2f", $0) }
                )
                .accessibilityIdentifier("analysis.delta")
            }
            if layout.showsSpeed {
                let factor = speedUnit.factorFromMetersPerSecond
                let speeds = series(analysis) { trace in
                    analysis.values(of: .speed, trace, at: grid).map {
                        .init(distance: $0.distance, value: $0.value * factor)
                    }
                }
                AnalysisTracePanel(
                    title: "Speed (\(speedUnit.symbol))", series: speeds, span: model.span, height: layout.traceHeight,
                    metresPerUnit: metresPerUnit,
                    unitSymbol: speedUnit.symbol, cursor: $model.cursor, format: { String(format: "%.0f", $0) }
                )
                .accessibilityIdentifier("analysis.speed")
            }
            ForEach(layout.channels, id: \.self) { role in
                let unit = model.unit(of: role)
                AnalysisTracePanel(
                    title: unit.isEmpty ? role.displayName : "\(role.displayName) (\(unit))",
                    series: series(analysis) { analysis.values(of: role, $0, at: grid) }, span: model.span,
                    height: layout.traceHeight, metresPerUnit: metresPerUnit, unitSymbol: unit, cursor: $model.cursor
                )
                .contextMenu { Button("Remove Trace") { model.layout.remove(role) } }
                .accessibilityIdentifier("analysis.trace.\(role.identifier)")
            }
            Text("Distance into \(analysis.reference.label) (\(distanceSymbol))")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func sidePanels(_ analysis: LapAnalysis) -> some View {
        VStack(spacing: 10) {
            if showsPicture { AnalysisPicturePanel(model: model, analysis: analysis, colors: colors) }
            if model.layout.showsMap {
                AnalysisMapPanel(analysis: analysis, colors: colors, cursor: model.cursor) {
                    model.zoom(toCornerAt: $0)
                }
                .frame(height: 260)
                .background(.background.secondary, in: RoundedRectangle(cornerRadius: 8))
            }
            if model.layout.showsFrictionCircle {
                AnalysisFrictionCircle(analysis: analysis, colors: colors, span: model.span, cursor: model.cursor)
                    .frame(height: 240)
                    .background(.background.secondary, in: RoundedRectangle(cornerRadius: 8))
            }
        }
        .frame(width: 260)
    }

    /// The picture shows when asked for and a chosen lap has one.
    private var showsPicture: Bool { model.layout.showsPicture && !model.footage.isEmpty }

    private func series(_ analysis: LapAnalysis, _ points: (LapAnalysis.Trace) -> [LapAnalysis.Point])
        -> [AnalysisSeries]
    {
        analysis.traces.map { trace in
            AnalysisSeries(id: trace.id, label: trace.label, color: colors[trace.id], points: points(trace))
        }
    }
}

/// Which panels show, the traces added under speed, and how tall they are.
struct AnalysisPanelsMenu: View {
    @Bindable var model: LapAnalysisModel

    var body: some View {
        Menu("Panels") {
            Toggle("Delta-T", isOn: $model.layout.showsDelta)
            Toggle("Speed", isOn: $model.layout.showsSpeed)
            Toggle("Track Map", isOn: $model.layout.showsMap)
            Toggle("Friction Circle", isOn: $model.layout.showsFrictionCircle)
            Toggle("Picture", isOn: $model.layout.showsPicture)
            Divider()
            Menu("Add Trace") {
                ForEach(model.traceableChannels.filter { !model.layout.channels.contains($0) }, id: \.self) { role in
                    Button(role.displayName) { model.layout.add(role) }
                }
            }
            Menu("Remove Trace") {
                ForEach(model.layout.channels, id: \.self) { role in
                    Button(role.displayName) { model.layout.remove(role) }
                }
            }
            .disabled(model.layout.channels.isEmpty)
            Divider()
            Button("Taller Traces") {
                model.layout.traceHeight = min(model.layout.traceHeight + 40, AnalysisLayout.traceHeights.upperBound)
            }
            Button("Shorter Traces") {
                model.layout.traceHeight = max(model.layout.traceHeight - 40, AnalysisLayout.traceHeights.lowerBound)
            }
        }
        .fixedSize()
        .help("Choose the panels and the channels traced; kept for next time")
        .accessibilityIdentifier("analysis.panels")
    }
}

/// What each lap reads at the cursor: its time there, how far behind the reference, its speed.
struct AnalysisReadout: View {
    let analysis: LapAnalysis
    let cursor: Double?
    let colors: [Color]
    let speedUnit: SpeedDisplayUnit
    let metresPerUnit: Double
    let distanceSymbol: String

    var body: some View {
        let readings = cursor.map { analysis.readings(at: $0, roles: [.speed]) } ?? []
        HStack(spacing: 16) {
            Text(
                cursor.map { place in
                    let corner = analysis.corner(at: place, margin: 0).map { " · \($0.title)" } ?? ""
                    return "\(Int((place / metresPerUnit).rounded())) \(distanceSymbol)\(corner)"
                } ?? "Move over a trace to read every lap at one place"
            )
            .foregroundStyle(.secondary)
            .accessibilityIdentifier("analysis.cursor")
            ForEach(readings) { reading in
                HStack(spacing: 4) {
                    Circle().fill(colors[reading.trace % colors.count]).frame(width: 8, height: 8).accessibilityHidden(
                        true)
                    Text(analysis.traces[reading.trace].label)
                    Text(TimeParsing.lapTimeString(reading.elapsed, decimals: 2)).monospacedDigit()
                    if reading.trace > 0 {
                        Text(String(format: "%+.2f s", reading.delta)).monospacedDigit()
                            .foregroundStyle(reading.delta > 0 ? Color.red : Color.green)
                    }
                    if let speed = reading.values[.speed] {
                        Text(speedUnit.text(metersPerSecond: speed)).monospacedDigit().foregroundStyle(.secondary)
                    }
                }
                .accessibilityElement(children: .combine)
            }
            Spacer()
        }
        .font(.callout)
        .lineLimit(1)
    }
}

/// The laps on offer, grouped by session, up to four ticked; the first ticked is the reference.
struct AnalysisLapList: View {
    @Bindable var model: LapAnalysisModel

    var body: some View {
        List {
            ForEach(model.groups) { group in
                Section {
                    ForEach(group.choices) { choice in
                        HStack(spacing: 6) {
                            Toggle(isOn: Binding(get: { model.isChosen(choice) }, set: { _ in model.toggle(choice) })) {
                                HStack(spacing: 6) {
                                    Circle().fill(model.color(of: choice) ?? Color.clear).frame(width: 10, height: 10)
                                        .accessibilityHidden(true)
                                    Text(choice.title)
                                }
                            }
                            .disabled(model.isFull && !model.isChosen(choice))
                            if model.isReference(choice) {
                                Text("Reference").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .contextMenu {
                            Button("Make Reference") { model.makeReference(choice) }
                                .disabled(!model.isChosen(choice) || model.isReference(choice))
                        }
                        .accessibilityIdentifier("analysis.lap.\(choice.id)")
                    }
                    if group.isLoading { ProgressView().controlSize(.small) }
                } header: {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(group.isHome ? "This Session" : group.title)
                        if !group.subtitle.isEmpty { Text(group.subtitle).font(.caption).foregroundStyle(.secondary) }
                    }
                }
            }
        }
        .accessibilityIdentifier("analysis.laps")
    }
}
