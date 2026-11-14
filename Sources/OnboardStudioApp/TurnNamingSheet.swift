import ProjectModel
import SwiftUI
import TelemetryKit

/// Which circuit and configuration to name the turns of, and the session whose best lap they are
/// named on.
struct TurnNamingRequest: Identifiable {
    let id = UUID()
    /// `LogbookFilter.circuitKey`: the circuit and its configuration (#549).
    let key: String
    let title: String
    let entry: LogbookEntry
}

/// Naming a circuit's turns from its card in the Logbook (#550).
///
/// Turn names could only be typed in a project's inspector, in a collapsed list reading Corner 1,
/// Corner 2…, with nothing to show which corner a field was. Here the circuit is drawn from its
/// best lap with each corner numbered, the field being typed in lights its corner on the map, and
/// the names are kept on the circuit, where the Logbook's Trends, goals, plans and Coaching read
/// them. They are pinned to that lap's bends (#548), so they stay on their turns on every lap.
struct TurnNamingSheet: View {
    let request: TurnNamingRequest
    /// The session's file, read off the main thread; `nil` when it cannot be found or read.
    let load: () async -> TelemetrySession?
    /// The names as they were, from the circuit's track definition.
    let pinned: [TurnName]
    let legacy: [String]
    /// The turn names to keep for the circuit, given on Done.
    let save: ([TurnName]) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var phase = Phase.loading
    @State private var corners: [Corner] = []
    @State private var path: [GeoPoint] = []
    @State private var labels: [String] = []
    /// What each field shows when it is empty: the corner's count, or the turns either side.
    @State private var placeholders: [String] = []
    @FocusState private var focused: Int?

    enum Phase { case loading, unreadable, noCorners, ready }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Name the Turns").font(.title2)
            Text(explanation).font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            content
            HStack {
                if phase == .ready {
                    Button("Number the Following Turns from Here", action: numberOn)
                        .disabled(focused.flatMap { CornerNaming.numbering(labels, from: $0) } == nil)
                        .help("Calls the turns after the one being typed in 4, 5, 6… after a 3 or a 3a")
                        .accessibilityIdentifier("turns.numberOn")
                }
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier("turns.cancel")
                Button("Done", action: commit).keyboardShortcut(.defaultAction)
                    .disabled(phase != .ready)
                    .accessibilityIdentifier("turns.done")
            }
        }
        .padding(20)
        .frame(width: 640)
        .task { await read() }
    }

    private var explanation: String {
        let when = request.entry.date.map { " on \($0.formatted(date: .abbreviated, time: .omitted))" } ?? ""
        return "\(request.title), as your best lap here\(when) drove it. Type what the circuit calls each "
            + "turn — 3a and the like. A name stays with its turn on every lap and every visit, and a "
            + "corner left blank among named ones is not one of the circuit's turns."
    }

    @ViewBuilder private var content: some View {
        switch phase {
        case .loading:
            ProgressView("Reading the lap…").frame(maxWidth: .infinity, minHeight: 300)
        case .unreadable:
            ContentUnavailableView(
                "The Lap Cannot Be Read", systemImage: "doc.questionmark",
                description: Text(
                    "The file of the best session here is not where the logbook has it. Find it, or add the "
                        + "session again, to name the turns on its lap.")
            )
            .frame(minHeight: 300)
        case .noCorners:
            ContentUnavailableView(
                "No Corners Found", systemImage: "point.topleft.down.to.point.bottomright.curvepath",
                description: Text(
                    "The best session here has no complete lap with a GPS trace to find corners in.")
            )
            .frame(minHeight: 300)
        case .ready:
            HStack(alignment: .top, spacing: 16) {
                TurnMap(path: path, corners: corners, labels: shown, highlighted: focused)
                    .frame(width: 280, height: 300)
                ScrollView {
                    Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 6) {
                        ForEach(corners.indices, id: \.self) { index in row(index) }
                    }
                    .padding(.trailing, 4)
                }
                .frame(height: 300)
            }
        }
    }

    private func row(_ index: Int) -> some View {
        GridRow {
            Text("Corner \(index + 1)").foregroundStyle(focused == index ? Color.accentColor : .primary)
            Text(corners[index].turnsRight ? "right" : "left").foregroundStyle(.secondary)
            TextField("Corner \(index + 1)", text: $labels[index], prompt: Text(placeholders[index]))
                .labelsHidden()
                .frame(width: 120)
                .focused($focused, equals: index)
                .accessibilityLabel("Corner \(index + 1) name")
                .accessibilityIdentifier("turns.name.\(index + 1)")
                .contextMenu {
                    Button("Number the Following Turns from Here") { numberOn(from: index) }
                        .disabled(CornerNaming.numbering(labels, from: index) == nil)
                }
        }
    }

    /// What the map writes at each corner: the typed name, else nothing for a corner left blank.
    private var shown: [String] { labels.map { $0.trimmingCharacters(in: .whitespaces) } }

    private func numberOn() { focused.map(numberOn(from:)) }

    private func numberOn(from index: Int) {
        if let numbered = CornerNaming.numbering(labels, from: index) { labels = numbered }
    }

    private func read() async {
        guard let session = await load() else {
            phase = .unreadable
            return
        }
        guard let best = LapDeltas.sessionBest(in: session), let profile = LapProfile(lap: best, in: session),
            let latitude = profile.latitude, let longitude = profile.longitude
        else {
            phase = .noCorners
            return
        }
        // The same lap and the same corners the logbook reads the session's corners from.
        let found = CornerDetector.corners(of: profile)
        guard !found.isEmpty else {
            phase = .noCorners
            return
        }
        let names = CornerNaming.names(for: found, pinned: pinned, legacy: legacy)
        corners = found
        path = zip(latitude, longitude).map { GeoPoint(latitude: $0, longitude: $1) }
        // A counted corner starts with its count typed in, so naming one turn 3a does not leave the
        // rest unnamed; one called by its neighbours starts blank, as the driver left it.
        labels = names.map { $0.source == .between ? "" : $0.label }
        placeholders = names.map(\.label)
        phase = .ready
    }

    private func commit() {
        save(CornerNaming.naming(corners, as: labels, pinned: pinned))
        dismiss()
    }
}

/// The circuit from above, drawn from one lap, with its corners named where they are.
struct TurnMap: View {
    let path: [GeoPoint]
    let corners: [Corner]
    let labels: [String]
    /// The corner whose field is being typed in, drawn in the accent colour.
    let highlighted: Int?

    var body: some View {
        Canvas { context, size in
            guard let projection = Projection(path: path, size: size, inset: 18) else { return }
            var line = Path()
            for (index, point) in path.enumerated() {
                let at = projection.place(point)
                if index == 0 { line.move(to: at) } else { line.addLine(to: at) }
            }
            context.stroke(line, with: .color(.secondary), style: StrokeStyle(lineWidth: 3, lineJoin: .round))
            for (index, corner) in corners.enumerated() {
                guard let latitude = corner.apexLatitude, let longitude = corner.apexLongitude else { continue }
                let at = projection.place(GeoPoint(latitude: latitude, longitude: longitude))
                let isHighlighted = index == highlighted
                let radius: CGFloat = isHighlighted ? 11 : 9
                let disc = Path(
                    ellipseIn: CGRect(x: at.x - radius, y: at.y - radius, width: 2 * radius, height: 2 * radius))
                context.fill(disc, with: .color(isHighlighted ? .accentColor : Color(nsColor: .controlBackgroundColor)))
                context.stroke(disc, with: .color(isHighlighted ? .accentColor : .secondary), lineWidth: 1)
                let label = index < labels.count && !labels[index].isEmpty ? labels[index] : "·"
                context.draw(
                    Text(label).font(.caption2.weight(.semibold))
                        .foregroundStyle(isHighlighted ? Color.white : Color.primary),
                    at: at)
            }
        }
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement()
        .accessibilityLabel("Map of the circuit with its corners numbered")
        .accessibilityIdentifier("turns.map")
    }

    /// Latitude and longitude onto the canvas, north up, the same scale both ways.
    struct Projection {
        let minLatitude: Double
        let minLongitude: Double
        let metresPerDegreeLongitude: Double
        let scale: Double
        let origin: CGPoint
        let height: Double

        init?(path: [GeoPoint], size: CGSize, inset: Double) {
            guard let first = path.first else { return nil }
            var low = first
            var high = first
            for point in path {
                low = GeoPoint(
                    latitude: min(low.latitude, point.latitude), longitude: min(low.longitude, point.longitude))
                high = GeoPoint(
                    latitude: max(high.latitude, point.latitude), longitude: max(high.longitude, point.longitude))
            }
            let metresPerDegreeLatitude = 111_195.0
            metresPerDegreeLongitude = metresPerDegreeLatitude * cos((low.latitude + high.latitude) / 2 * .pi / 180)
            let width = (high.longitude - low.longitude) * metresPerDegreeLongitude
            height = (high.latitude - low.latitude) * metresPerDegreeLatitude
            guard width > 0 || height > 0 else { return nil }
            scale = min((size.width - 2 * inset) / max(width, 1), (size.height - 2 * inset) / max(height, 1))
            origin = CGPoint(x: (size.width - width * scale) / 2, y: (size.height - height * scale) / 2)
            minLatitude = low.latitude
            minLongitude = low.longitude
        }

        func place(_ point: GeoPoint) -> CGPoint {
            let east = (point.longitude - minLongitude) * metresPerDegreeLongitude
            let north = (point.latitude - minLatitude) * 111_195.0
            return CGPoint(x: origin.x + east * scale, y: origin.y + (height - north) * scale)
        }
    }
}
