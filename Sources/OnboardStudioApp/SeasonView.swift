import AppKit
import Charts
import ProjectModel
import SwiftUI
import TelemetryKit
import UniformTypeIdentifiers

/// A year on one page (#355): the numbers, the bests per circuit, the chart of every circuit's
/// best across the year, the corner that moved most, and the plans still open — exported as a
/// one-page PDF or a 9:16 card.
struct SeasonView: View {
    let entries: [LogbookEntry]
    let plans: [TrackDefinition]
    /// The goals set (#461): those reached in the year are listed on its page.
    var goals: [Goal] = []
    let onOpen: (UUID) -> Void
    @State private var year: Int = 0
    @State private var car = ""
    @State private var message: String?

    private var years: [Int] { SeasonSummary.years(in: entries) }
    private var cars: [String] { Array(Set(entries.map(\.car).filter { !$0.isEmpty })).sorted() }
    private var summary: SeasonSummary {
        SeasonSummary.make(entries: entries, year: year, car: car.isEmpty ? nil : car, plans: plans)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                SeasonPage(
                    summary: summary, entries: entries, forPrint: false, goalsReached: goalsReached, onOpen: onOpen)
                if let message { Text(message).font(.callout).foregroundStyle(.secondary) }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear { if year == 0 { year = years.first ?? Calendar.current.component(.year, from: Date()) } }
        .accessibilityIdentifier("logbook.season")
    }

    /// "1:40.00 lap at Stadium, reached on 12 Oct 2026", for the goals first met in the year.
    private var goalsReached: [String] {
        let titles = Dictionary(
            LogbookFilter.circuits(in: entries).compactMap { group -> (String, String)? in
                guard case .circuit(let id, let title) = group.scope else { return nil }
                return (id, title)
            }, uniquingKeysWith: { first, _ in first })
        let calendar = Calendar.current
        return goals.map { GoalProgress.make($0, entries: entries) }
            .filter { progress in
                guard let day = progress.reachedOn, calendar.component(.year, from: day) == year else { return false }
                return car.isEmpty || progress.goal.car.isEmpty || progress.goal.car == car
            }
            .sorted { ($0.reachedOn ?? .distantPast) < ($1.reachedOn ?? .distantPast) }
            .map { progress in
                let title = CircuitGoalsSection.heading(progress.goal, speed: LogbookWindow.speedUnit)
                let place = titles[progress.goal.circuitKey] ?? progress.goal.circuitKey
                let day = progress.reachedOn?.formatted(date: .abbreviated, time: .omitted) ?? ""
                return "\(title) at \(place), reached on \(day)"
            }
    }

    private var header: some View {
        HStack {
            Picker("Year", selection: $year) { ForEach(years, id: \.self) { Text(String($0)).tag($0) } }
                .frame(maxWidth: 140)
                .accessibilityIdentifier("logbook.season.year")
            if !cars.isEmpty {
                Picker("Car", selection: $car) {
                    Text("Every car").tag("")
                    ForEach(cars, id: \.self) { Text($0).tag($0) }
                }
                .frame(maxWidth: 220)
                .accessibilityIdentifier("logbook.season.car")
            }
            Spacer()
            Button("Export as PDF…") { exportPDF() }.accessibilityIdentifier("logbook.season.pdf")
            Button("Export Card…") { exportCard() }.accessibilityIdentifier("logbook.season.card")
        }
    }

    // MARK: - Out the door

    private func exportPDF() {
        let summary = summary
        guard
            let url = OpenPanels.chooseDocumentDestination(
                title: "Export Season", suggestedName: "\(summary.title) season", type: .pdf, fileExtension: "pdf")
        else { return }
        do {
            try SeasonExport.writePDF(summary, entries: entries, goalsReached: goalsReached, to: url)
            message = "Wrote \(url.lastPathComponent)."
        } catch {
            message = "Could not write the PDF: \(error.localizedDescription)"
        }
    }

    private func exportCard() {
        let summary = summary
        guard
            let url = OpenPanels.chooseDocumentDestination(
                title: "Export Season Card", suggestedName: "\(summary.title) card", type: .png, fileExtension: "png")
        else { return }
        do {
            try SeasonExport.writeCard(summary, to: url)
            message = "Wrote \(url.lastPathComponent)."
        } catch {
            message = "Could not write the card: \(error.localizedDescription)"
        }
    }
}

/// The page itself, in the window or on paper.
struct SeasonPage: View {
    let summary: SeasonSummary
    let entries: [LogbookEntry]
    let forPrint: Bool
    /// The goals first reached in the year (#461), a line each.
    var goalsReached: [String] = []
    var onOpen: (UUID) -> Void = { _ in }

    private var ink: Color { forPrint ? .black : .primary }
    private var dim: Color { forPrint ? Color(white: 0.4) : .secondary }
    private var heading: Font { forPrint ? .system(size: 12, weight: .semibold) : .subheadline.weight(.semibold) }
    private var body10: Font { forPrint ? .system(size: 10) : .callout }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(summary.title).font(forPrint ? .system(size: 22, weight: .bold) : .title2.weight(.semibold))
                Text(summary.lines.prefix(3).joined(separator: " · ")).font(forPrint ? .system(size: 11) : .callout)
                    .foregroundStyle(dim)
                    .accessibilityIdentifier("logbook.season.summary")
            }
            if !summary.circuitBests.isEmpty {
                bests
                chart
            } else {
                Text("No sessions in this year\(summary.car.map { $0.isEmpty ? "" : " in the \($0)" } ?? "").")
                    .foregroundStyle(dim)
            }
            movements
            if !goalsReached.isEmpty { goals }
            if !summary.openPlans.isEmpty { plans }
        }
        .foregroundStyle(ink)
    }

    private var bests: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Best at each circuit").font(heading)
            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 3) {
                ForEach(summary.circuitBests) { best in
                    GridRow {
                        Text(best.title)
                        Text(TimeParsing.lapTimeString(best.best)).monospacedDigit()
                        Text(best.date.map { $0.formatted(date: .abbreviated, time: .omitted) } ?? "—")
                            .foregroundStyle(dim)
                        Text(best.car).foregroundStyle(dim)
                        Text("\(best.visits) visit\(best.visits == 1 ? "" : "s")").foregroundStyle(dim)
                        if best.isNewPersonalBest {
                            Image(systemName: "star.fill").foregroundStyle(.yellow)
                                .accessibilityLabel("New personal best")
                        } else {
                            Text("")
                        }
                    }
                    .font(body10)
                }
            }
        }
    }

    private struct Row: Identifiable {
        var id: String { "\(circuit)-\(date)" }
        var circuit: String
        var date: Date
        var best: Double
        var entryID: UUID
    }

    /// One point per visit — a track day's best session (#426) — so a day of several sessions is
    /// not a vertical zigzag on a year-long axis.
    private var rows: [Row] {
        let calendar = Calendar(identifier: .gregorian)
        return summary.circuitBests.flatMap { best in
            let sessions = LogbookTrends.points(for: entries, circuitKey: best.circuitKey, car: summary.car)
                .compactMap { point -> Row? in
                    let entry = entries.first { $0.id == point.entryID } ?? LogbookEntry.placeholder
                    guard SeasonSummary.year(of: entry) == summary.year, let seconds = point.best else { return nil }
                    return Row(circuit: best.title, date: point.date, best: seconds, entryID: point.entryID)
                }
            return Dictionary(grouping: sessions) { calendar.startOfDay(for: $0.date) }.values
                .compactMap { day in day.min { $0.best < $1.best } }
                .sorted { $0.date < $1.date }
        }
    }

    private var chart: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Best lap by visit").font(heading)
            Chart(rows) { row in
                LineMark(x: .value("Visit", row.date), y: .value("Seconds", row.best))
                    .foregroundStyle(by: .value("Circuit", row.circuit))
                PointMark(x: .value("Visit", row.date), y: .value("Seconds", row.best))
                    .foregroundStyle(by: .value("Circuit", row.circuit))
            }
            .chartYScale(domain: .automatic(includesZero: false))
            .chartYAxis {
                AxisMarks { value in
                    AxisGridLine()
                    AxisValueLabel { Text(TimeParsing.lapTimeString(value.as(Double.self) ?? 0)).monospacedDigit() }
                }
            }
            .frame(height: forPrint ? 160 : 200)
            .accessibilityLabel("Best lap by visit, per circuit")
            .accessibilityValue(summary.lines.joined(separator: ". "))
            .accessibilityIdentifier("logbook.season.chart")
        }
    }

    private var movements: some View {
        VStack(alignment: .leading, spacing: 3) {
            if let improved = summary.mostImproved {
                Label(
                    "Most improved: \(improved.circuitTitle) turn \(improved.label), "
                        + String(format: "%.2f s quicker than the visit before", -improved.change),
                    systemImage: "arrow.up.right")
            }
            if let costly = summary.mostCostly {
                Label(
                    "Most costly: \(costly.circuitTitle) turn \(costly.label), "
                        + String(format: "%.2f s slower than the visit before", costly.change),
                    systemImage: "arrow.down.right")
            }
        }
        .font(body10)
    }

    private var goals: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Goals reached").font(heading)
            ForEach(goalsReached, id: \.self) { line in
                Label(line, systemImage: "checkmark.seal.fill").font(body10)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("logbook.season.goals")
    }

    private var plans: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Still planned").font(heading)
            ForEach(summary.openPlans) { plan in
                Text(plan.circuitTitle).font(body10.weight(.semibold))
                ForEach(plan.experiments, id: \.self) { Text("• \($0)").font(forPrint ? .system(size: 9) : .callout) }
            }
        }
    }
}

extension LogbookEntry {
    /// An entry that is nowhere, for lookups that must not fail.
    static let placeholder = LogbookEntry(file: .init(path: "", contentHash: "", byteCount: 0, importerID: ""))
}

/// The season on paper and as a 9:16 card for a phone.
enum SeasonExport {
    static let pageSize = CGSize(width: 612, height: 792)
    static let cardSize = CGSize(width: 1080, height: 1920)

    enum Failure: Error, LocalizedError {
        case cannotCreate
        var errorDescription: String? { "The file could not be created at that location." }
    }

    @MainActor
    static func writePDF(
        _ summary: SeasonSummary, entries: [LogbookEntry], goalsReached: [String] = [], to url: URL
    ) throws {
        let page = SeasonPage(summary: summary, entries: entries, forPrint: true, goalsReached: goalsReached)
            .padding(36)
            .frame(width: pageSize.width, height: pageSize.height, alignment: .topLeading)
            .background(Color.white)
        let renderer = ImageRenderer(content: page)
        renderer.proposedSize = ProposedViewSize(pageSize)
        var box = CGRect(origin: .zero, size: pageSize)
        guard let consumer = CGDataConsumer(url: url as CFURL),
            let context = CGContext(consumer: consumer, mediaBox: &box, nil)
        else { throw Failure.cannotCreate }
        renderer.render { _, draw in
            context.beginPDFPage(nil)
            draw(context)
            context.endPDFPage()
        }
        context.closePDF()
    }

    /// The card: the title and the headline lines, big, on a dark ground, 1080 × 1920 — the
    /// Social template's shape, as a picture to post.
    @MainActor
    static func writeCard(_ summary: SeasonSummary, to url: URL) throws {
        let renderer = ImageRenderer(content: SeasonCard(summary: summary))
        renderer.proposedSize = ProposedViewSize(cardSize)
        renderer.scale = 1
        guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
            let bitmap = NSBitmapImageRep(data: tiff), let png = bitmap.representation(using: .png, properties: [:])
        else { throw Failure.cannotCreate }
        try png.write(to: url, options: .atomic)
    }
}

struct SeasonCard: View {
    let summary: SeasonSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            Spacer()
            Text(summary.title).font(.system(size: 88, weight: .bold)).foregroundStyle(.white)
            ForEach(summary.lines, id: \.self) { line in
                Text(line).font(.system(size: 40, weight: .medium)).foregroundStyle(.white.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Text("Onboard Studio").font(.system(size: 28)).foregroundStyle(.white.opacity(0.5))
        }
        .padding(80)
        .frame(width: SeasonExport.cardSize.width, height: SeasonExport.cardSize.height, alignment: .leading)
        .background(Color(red: 0.07, green: 0.07, blue: 0.08))
    }
}
