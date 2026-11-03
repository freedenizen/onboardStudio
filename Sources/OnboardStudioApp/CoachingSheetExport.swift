import AppKit
import ProjectModel
import SwiftUI
import TelemetryKit
import UniformTypeIdentifiers

extension FocusedValues {
    /// The Coaching window's sheet while it is the key window and has a reading: for
    /// File ▸ Export Coaching Sheet (#331).
    @Entry var coachingSheet: CoachingSheet?
}

/// File ▸ Export Coaching Sheet as PDF… / as Markdown…, there while the Coaching window has a
/// lap read.
struct CoachingSheetCommands: Commands {
    @FocusedValue(\.coachingSheet) private var sheet
    @FocusedValue(\.editor) private var editor

    var body: some Commands {
        CommandGroup(after: .importExport) {
            if let sheet {
                Button("Export Coaching Sheet as PDF…") { editor?.exportCoachingSheet(sheet, as: .pdf) }
                Button("Export Coaching Sheet as Markdown…") { editor?.exportCoachingSheet(sheet, as: .markdown) }
                Divider()
            }
        }
    }
}

enum CoachingSheetFormat {
    case pdf
    case markdown

    var type: UTType { self == .pdf ? .pdf : UTType(filenameExtension: "md") ?? .plainText }
    var fileExtension: String { self == .pdf ? "pdf" : "md" }
}

extension EditorModel {
    func exportCoachingSheet(_ sheet: CoachingSheet, as format: CoachingSheetFormat) {
        guard
            let url = OpenPanels.chooseDocumentDestination(
                title: "Export Coaching Sheet", suggestedName: sheet.fileStem, type: format.type,
                fileExtension: format.fileExtension)
        else { return }
        do {
            switch format {
            case .pdf: try CoachingSheetPDF.write(sheet, to: url)
            case .markdown: try sheet.markdown.write(to: url, atomically: true, encoding: .utf8)
            }
            statusMessage = "Exported the coaching sheet as \(url.lastPathComponent)."
        } catch {
            statusMessage = "Could not write the coaching sheet: \(error.localizedDescription)"
        }
    }
}

/// One US Letter page, drawn by `CoachingSheetView` through `ImageRenderer`.
enum CoachingSheetPDF {
    static let pageSize = CGSize(width: 612, height: 792)

    enum Failure: Error, LocalizedError {
        case cannotCreate
        var errorDescription: String? { "The PDF could not be created at that location." }
    }

    @MainActor
    static func write(_ sheet: CoachingSheet, to url: URL) throws {
        let renderer = ImageRenderer(
            content: CoachingSheetView(sheet: sheet).frame(width: pageSize.width, height: pageSize.height))
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
}

/// The printed page: black on white, so it reads the same in either appearance and on paper.
struct CoachingSheetView: View {
    let sheet: CoachingSheet
    private let ink = Color.black
    private let dim = Color(white: 0.4)

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(sheet.title.isEmpty ? "Coaching sheet" : sheet.title) — Lap \(sheet.lapNumber)")
                    .font(.system(size: 20, weight: .bold))
                if !sheet.subtitle.isEmpty { Text(sheet.subtitle).font(.system(size: 10)).foregroundStyle(dim) }
                Text(sheet.headline).font(.system(size: 11, weight: .semibold)).padding(.top, 4)
                ForEach(sheet.notes, id: \.self) { Text($0).font(.system(size: 9)).foregroundStyle(dim) }
            }
            HStack(alignment: .top, spacing: 16) {
                map.frame(width: 200, height: 200)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Where the time went").font(.system(size: 12, weight: .semibold))
                    if sheet.opportunities.isEmpty {
                        Text("Nothing lost: every corner matched the reference.").font(.system(size: 9))
                    }
                    ForEach(Array(sheet.opportunities.enumerated()), id: \.offset) { index, item in
                        VStack(alignment: .leading, spacing: 1) {
                            Text("\(index + 1). \(item.headline)").font(.system(size: 10, weight: .semibold))
                            ForEach(item.evidence, id: \.self) { Text("• \($0)").font(.system(size: 9)) }
                            Text("Try: \(item.suggestion)").font(.system(size: 9)).foregroundStyle(dim)
                        }
                    }
                }
            }
            table
            if let plan = sheet.plan, !plan.experiments.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Next session, try…").font(.system(size: 12, weight: .semibold))
                    ForEach(Array(plan.experiments.enumerated()), id: \.element.id) { index, experiment in
                        Text("\(index + 1). \(experiment.title) — \(experiment.text)").font(.system(size: 10))
                    }
                }
            }
            ForEach(sheet.warnings, id: \.self) { Text($0).font(.system(size: 8)).foregroundStyle(dim) }
            Spacer(minLength: 0)
            Text("Onboard Studio").font(.system(size: 8)).foregroundStyle(dim)
        }
        .foregroundStyle(ink)
        .padding(36)
        .frame(width: CoachingSheetPDF.pageSize.width, height: CoachingSheetPDF.pageSize.height, alignment: .topLeading)
        .background(Color.white)
    }

    private var map: some View {
        Canvas { context, size in
            let inset = 12.0
            let scale = min(size.width, size.height) - 2 * inset
            func place(_ point: CoachingSheet.Point) -> CGPoint {
                CGPoint(x: inset + point.x * scale, y: inset + point.y * scale)
            }
            var path = Path()
            if let first = sheet.outline.first {
                path.move(to: place(first))
                for point in sheet.outline.dropFirst() { path.addLine(to: place(point)) }
            }
            context.stroke(path, with: .color(Color(white: 0.3)), lineWidth: 1.5)
            for corner in sheet.corners {
                let at = place(corner.point)
                let disc = Path(ellipseIn: CGRect(x: at.x - 6, y: at.y - 6, width: 12, height: 12))
                context.fill(disc, with: .color(.white))
                context.stroke(disc, with: .color(.black), lineWidth: 0.8)
                context.draw(
                    Text(corner.label).font(.system(size: 7, weight: .semibold)).foregroundStyle(.black), at: at)
            }
        }
        .accessibilityHidden(true)
    }

    private var table: some View {
        let header = ["Turn", "Lost", "Phase", "Brake", "Min speed", "Where", "Exit", "Throttle", "Consistent"]
        let format = CoachingNotes.Formatter(units: sheet.units)
        return Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 2) {
            GridRow {
                ForEach(header, id: \.self) { Text($0).font(.system(size: 8, weight: .semibold)) }
            }
            Divider()
            ForEach(sheet.rows) { row in
                GridRow {
                    Text(row.label)
                    Text((row.timeLost >= 0 ? "+" : "−") + format.seconds(abs(row.timeLost)))
                    Text(row.phase)
                    Text(row.brake)
                    Text(row.minimumSpeed)
                    Text(row.minimumPoint)
                    Text(row.exitSpeed)
                    Text(row.throttle)
                    Text(row.consistent)
                }
                .font(.system(size: 8))
            }
        }
    }
}

extension CoachingContent {
    /// The page for File ▸ Export Coaching Sheet (#331): this reading, the project's details and plan.
    func sheet(_ analysis: CoachingAnalysis, selection: CoachingSelection, session: TelemetrySession) -> CoachingSheet {
        let details = editor.project.details
        func text(_ value: String) -> String? {
            let trimmed = value.trimmingCharacters(in: .whitespaces)
            return trimmed.isEmpty ? nil : trimmed
        }
        let title = text(details.track) ?? session.info.trackName ?? ""
        let subtitle = [text(details.date), text(details.driver), text(details.car), text(details.event)]
            .compactMap { $0 }.joined(separator: " · ")
        return CoachingSheet(
            analysis: analysis, lapNumber: selection.lapNumber, units: units, title: title, subtitle: subtitle,
            plan: editor.project.plan, warnings: analysis.warnings.map(describe))
    }

    func referenceName(_ reference: CoachingSettings.Reference) -> String {
        switch reference {
        case .sessionBest: CoachingReference.sessionBest.phrase
        case .lap(let number): CoachingReference.lap(number).phrase
        case .fastestRolling: CoachingReference.fastestRolling.phrase
        case .compositeOptimal: CoachingReference.compositeOptimal.phrase
        case .otherInput(let id, let lap): "\(editor.project.input(id)?.label ?? "the other file") lap \(lap)"
        }
    }

    func describe(_ warning: CoachingWarning) -> String {
        switch warning {
        case .approximateAlignment:
            "The two laps could not be lined up by place; distances are approximate."
        case .pedalsFromSpeedTrace:
            "No brake or throttle channel: brake and throttle points were read from the speed trace."
        case .seamInCorner(let labels):
            "The reference changes lap inside turn \(labels.joined(separator: ", ")), so its speed can step there."
        case .tooFewLapsForConsistency:
            "Fewer than three flying laps: nothing to say about consistency."
        }
    }
}
