import ProjectModel
import RenderKit
import SwiftUI
import TelemetryKit

/// Laps raced round the circuit in 3D (#415): a window beside the document or the logbook, the
/// pattern the Coaching window set. Window ▸ Replay (⌃⌘R), Replay… on a logbook session, or
/// Replay from the Coaching window.
struct ReplayWindow: View {
    static let windowID = "replay"

    @AppStorage(Preferences.speedUnit.key) private var appSpeedUnit = Preferences.speedUnit.unset
    private var model = ReplayModel.shared
    private var active = ActiveEditor.shared

    /// The front project's laps.
    static func open(_ openWindow: OpenWindowAction) {
        ReplayModel.shared.showFrontProject(editor: ActiveEditor.shared.editor)
        openWindow(id: windowID)
    }

    /// A logbook session's laps.
    static func open(_ openWindow: OpenWindowAction, entry: LogbookEntry) {
        ReplayModel.shared.show(entry: entry)
        openWindow(id: windowID)
    }

    var body: some View {
        Group {
            if !model.hasSource {
                ContentUnavailableView(
                    "Nothing to Replay", systemImage: "car.side",
                    description: Text(
                        "Select a session in the Logbook and choose Replay…, or open a project with laps and choose "
                            + "Window ▸ Replay, to race its laps round the circuit."))
            } else if let problem = model.problem {
                ContentUnavailableView(
                    "The Session Did Not Load", systemImage: "exclamationmark.triangle", description: Text(problem))
            } else if model.isLoading {
                ProgressView("Reading the session…").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HSplitView {
                    lapList.frame(minWidth: 240, idealWidth: 280, maxWidth: 360)
                    stage.frame(minWidth: 640, minHeight: 420).layoutPriority(1)
                }
            }
        }
        .frame(minWidth: 900, minHeight: 480)
        .toolbar { toolbar }
        // Window ▸ Replay (⌃⌘R) opens the scene with nothing asked for: the front project's laps,
        // when there is one, are what the user means.
        .onAppear {
            if !model.hasSource, let editor = active.editor { model.showFrontProject(editor: editor) }
        }
    }

    // MARK: - Laps

    private var lapList: some View {
        List {
            ForEach(model.groups) { group in
                Section {
                    ForEach(group.choices) { choice in
                        Toggle(isOn: Binding(get: { model.isChosen(choice) }, set: { _ in model.toggle(choice) })) {
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(model.color(of: choice).map { Color($0) } ?? Color.clear)
                                    .frame(width: 10, height: 10)
                                    .accessibilityHidden(true)
                                Text(choice.title)
                            }
                        }
                        .accessibilityIdentifier("replay.lap.\(choice.id)")
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
        .accessibilityIdentifier("replay.laps")
    }

    // MARK: - The stage

    @ViewBuilder private var stage: some View {
        ZStack {
            if model.scene != nil {
                ReplaySceneHost(model: model)
                overlays
            } else if model.isBuilding {
                ProgressView("Building the circuit…")
            } else if let problem = model.buildProblem {
                ContentUnavailableView("No Road to Draw", systemImage: "road.lanes", description: Text(problem))
            } else {
                ContentUnavailableView(
                    "Choose Laps", systemImage: "checklist",
                    description: Text("Tick the laps to race in the list; each gets a colour of its own."))
            }
        }
    }

    private var overlays: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top) {
                hud
                Spacer()
                ReplayMiniMap(model: model).frame(width: 180, height: 180)
            }
            .padding(12)
            Spacer()
            VStack(spacing: 8) {
                standings
                transport
            }
            .padding(12)
        }
        .allowsHitTesting(true)
    }

    private var hud: some View {
        Group {
            if let watched = model.watched,
                let hud = model.hud(speedUnit: (SpeedUnitSetting(rawValue: appSpeedUnit) ?? .automatic).shown())
            {
                VStack(alignment: .leading, spacing: 4) {
                    Text(watched.lap.label).font(.headline).accessibilityIdentifier("replay.hud.lap")
                    if !watched.lap.subtitle.isEmpty {
                        Text(watched.lap.subtitle).font(.caption).foregroundStyle(.secondary)
                    }
                    Text(hud.speed).font(.system(size: 28, weight: .bold, design: .rounded)).monospacedDigit()
                        .accessibilityIdentifier("replay.hud.speed")
                    HStack(spacing: 12) {
                        LabeledContent("Lap", value: hud.lapTime).accessibilityIdentifier("replay.hud.time")
                        LabeledContent("Gap", value: hud.gap).accessibilityIdentifier("replay.hud.gap")
                    }
                    .font(.callout).monospacedDigit()
                }
                .padding(10)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
            }
        }
    }

    private var standings: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(Array(model.standings.enumerated()), id: \.element.id) { index, standing in
                    Button {
                        model.followed = standing.lap.id
                    } label: {
                        HStack(spacing: 8) {
                            Text("\(index + 1)").foregroundStyle(.secondary).frame(width: 16, alignment: .trailing)
                            Circle().fill(color(of: standing.lap)).frame(width: 10, height: 10).accessibilityHidden(
                                true)
                            Text(standing.lap.label).lineLimit(1)
                            Spacer(minLength: 12)
                            Text(standing.gapSeconds > 0 ? "+\(String(format: "%.2f", standing.gapSeconds))" : "—")
                                .foregroundStyle(.secondary).monospacedDigit()
                        }
                        .font(.callout)
                        .padding(.vertical, 2)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(
                        "\(index + 1), \(standing.lap.label), gap "
                            + "\(String(format: "%.2f", standing.gapSeconds)) seconds"
                    )
                    .accessibilityHint("Follow this car")
                    .accessibilityIdentifier("replay.standing.\(index + 1)")
                }
            }
            .padding(10)
            .frame(width: 300, alignment: .leading)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
            Spacer()
        }
    }

    private var transport: some View {
        HStack(spacing: 10) {
            Button(model.isPlaying ? "Pause" : "Play", systemImage: model.isPlaying ? "pause.fill" : "play.fill") {
                model.togglePlaying()
            }
            .labelStyle(.iconOnly)
            .keyboardShortcut(.space, modifiers: [])
            .help(model.isPlaying ? "Pause the replay (Space)" : "Play the replay (Space)")
            .accessibilityIdentifier("replay.play")
            Slider(
                value: Binding(get: { model.time }, set: { model.seek(to: $0) }), in: 0...max(model.duration, 0.01)
            ) {
                Text("Replay position")
            }
            .labelsHidden()
            .accessibilityValue(TimeParsing.lapTimeString(model.time, decimals: 1))
            .accessibilityIdentifier("replay.scrubber")
            Text(TimeParsing.lapTimeString(model.time, decimals: 1)).monospacedDigit().font(.callout)
                .frame(width: 64, alignment: .trailing)
                .accessibilityIdentifier("replay.time")
        }
        .padding(10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
    }

    private func color(of lap: ReplayLap) -> Color {
        model.choice(of: lap).flatMap { model.color(of: $0) }.map { Color($0) } ?? .secondary
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            Picker("Camera", selection: Binding(get: { model.camera }, set: { model.camera = $0 })) {
                ForEach(ReplayCamera.allCases, id: \.self) { Text($0.displayName).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .help("Chase, trackside, above, in car, or a free camera you drag (1–5)")
            .accessibilityIdentifier("replay.camera")
        }
        ToolbarItem(placement: .primaryAction) {
            Menu {
                ForEach(0..<(model.scene?.cornerCount ?? 0), id: \.self) { index in
                    Button("Turn \(index + 1)") { model.goToCorner(index) }
                }
            } label: {
                Label("Go to Turn", systemImage: "arrow.turn.up.right")
            }
            .disabled((model.scene?.cornerCount ?? 0) == 0)
            .accessibilityLabel("Go to Turn")
            .help("Jump to a few seconds before a corner")
            .accessibilityIdentifier("replay.goToTurn")
        }
        ToolbarItem(placement: .primaryAction) {
            Menu {
                ForEach([0.25, 0.5, 1.0, 2.0], id: \.self) { rate in
                    Button(rate == 1 ? "Normal speed" : "\(rate.formatted())×") { model.rate = rate }
                }
            } label: {
                Label("Speed", systemImage: "gauge.with.needle")
            }
            .accessibilityLabel("Replay Speed")
            .help("How fast the replay runs")
            .accessibilityIdentifier("replay.rate")
        }
    }
}

/// The circuit from above, with the cars on it and the turns numbered.
struct ReplayMiniMap: View {
    let model: ReplayModel

    var body: some View {
        Canvas { context, size in
            guard let field = model.field else { return }
            let points = field.track.samples.map { CGPoint(x: $0.position.x, y: -$0.position.y) }
            guard let first = points.first else { return }
            var minX = first.x, maxX = first.x, minY = first.y, maxY = first.y
            for point in points {
                minX = min(minX, point.x)
                maxX = max(maxX, point.x)
                minY = min(minY, point.y)
                maxY = max(maxY, point.y)
            }
            let span = max(maxX - minX, maxY - minY, 1)
            let scale = (min(size.width, size.height) - 24) / span
            func place(_ point: CGPoint) -> CGPoint {
                CGPoint(
                    x: 12 + (point.x - minX) * scale + (size.width - 24 - (maxX - minX) * scale) / 2,
                    y: 12 + (point.y - minY) * scale + (size.height - 24 - (maxY - minY) * scale) / 2)
            }
            var path = Path()
            path.move(to: place(first))
            for point in points.dropFirst() { path.addLine(to: place(point)) }
            path.closeSubpath()
            context.stroke(path, with: .color(.primary.opacity(0.7)), lineWidth: 3)
            for (index, corner) in field.track.corners.enumerated() {
                let sample = field.track.sample(atDistance: corner.apexDistance)
                let at = place(CGPoint(x: sample.position.x, y: -sample.position.y))
                context.draw(
                    Text("T\(index + 1)").font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary), at: at)
            }
            for (index, standing) in model.standings.enumerated() {
                let placement = standing.lap.position(atElapsed: model.time)
                let at = place(CGPoint(x: placement.point.x, y: -placement.point.y))
                let color =
                    model.choice(of: standing.lap).flatMap { model.color(of: $0) }.map { Color($0) } ?? .secondary
                context.fill(
                    Path(ellipseIn: CGRect(x: at.x - 4, y: at.y - 4, width: 8, height: 8)), with: .color(color))
                if index == 0 {
                    context.stroke(
                        Path(ellipseIn: CGRect(x: at.x - 5.5, y: at.y - 5.5, width: 11, height: 11)),
                        with: .color(.primary), lineWidth: 1)
                }
            }
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .accessibilityLabel("Track map with the cars")
        .accessibilityIdentifier("replay.minimap")
    }
}
