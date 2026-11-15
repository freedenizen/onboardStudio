import ProjectModel
import SwiftUI
import TelemetryKit

/// A session's laps (#557): each lap's time, how far it was off the best, its sector times and
/// its top and minimum speed, with the best of each column in the accent colour, as a timing
/// screen shows them. Too narrow for all of it, the speeds give way first, saying so, then it
/// scrolls.
struct SessionLapTable: View {
    let entry: LogbookEntry
    let speedUnit: SpeedDisplayUnit
    /// The file is being read for the sectors and speeds of a session entered before they were kept.
    var readingSplits = false
    /// Leaves a lap out of the figures for a reason, or counts it again (#554); `false` when the
    /// file could not be read.
    var markLap: ((Int, LapMark.Reason?) async -> Bool)?
    @State private var markFailed = false

    private var sectorCount: Int { entry.sectorCount }
    private var hasSpeeds: Bool { entry.laps.contains { $0.topSpeed != nil } }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Laps").font(.subheadline.weight(.semibold))
            ViewThatFits(in: .horizontal) {
                table(speeds: hasSpeeds)
                VStack(alignment: .leading, spacing: 4) {
                    table(speeds: false)
                    // Where the speeds went, so a narrow detail does not hide that there are any.
                    if hasSpeeds {
                        Text("Drag the detail wider for each lap's top and lowest speed.")
                            .font(.caption).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("logbook.laps.speedsHidden")
                    }
                }
                ScrollView(.horizontal) { table(speeds: hasSpeeds) }
            }
            if markFailed {
                Text("The session's file could not be read, so the lap was not changed. It may have moved.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if readingSplits {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Reading sector times and speeds…")
                }
                .font(.caption).foregroundStyle(.secondary)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("logbook.laps.reading")
            } else if sectorCount > 0 {
                Text("The quickest of each column is in colour; a dash is a sector the lap did not time.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("logbook.laps")
    }

    private func table(speeds: Bool) -> some View {
        let bestSectors = entry.bestSectors
        return Grid(alignment: .trailing, horizontalSpacing: 12, verticalSpacing: 3) {
            GridRow {
                Text("Lap").gridColumnAlignment(.leading)
                Text("Time")
                Text("Gap").help("How far the lap was off the session's best")
                ForEach(0..<sectorCount, id: \.self) { index in
                    Text(SectorLayout.name(of: index)).help("Sector \(index + 1)'s time")
                }
                if speeds {
                    Text("Top").help("The lap's top speed, in \(speedUnit.symbol)")
                    Text("Min").help("The lap's lowest speed, in \(speedUnit.symbol): its slowest corner")
                }
            }
            .font(.caption.bold()).foregroundStyle(.secondary)
            ForEach(entry.laps, id: \.number) { lap in
                GridRow {
                    lapCell(lap)
                    timeCell(lap)
                        .contextMenu { lapMarkItems(lap) }
                    gapCell(lap)
                    ForEach(0..<sectorCount, id: \.self) { index in
                        sectorCell(lap, index, best: bestSectors[index])
                    }
                    if speeds {
                        speedCell(lap.topSpeed, best: entry.bestTopSpeed, lap: lap, column: .top)
                        speedCell(lap.minSpeed, best: entry.bestMinSpeed, lap: lap, column: .min)
                    }
                }
                .font(.callout.monospacedDigit())
            }
        }
        .fixedSize()
    }

    // MARK: - Cells

    /// The lap's number: a menu to leave it out or count it again (#554), where the Logbook can.
    @ViewBuilder private func lapCell(_ lap: LogbookEntry.LapRecord) -> some View {
        if let markLap {
            LapCountsMenu(lap: lap, markLap: markLap) { markFailed = !$0 }
                .contextMenu { lapMarkItems(lap) }
        } else {
            Text("Lap \(lap.number)").accessibilityIdentifier("logbook.lap.\(lap.number)")
        }
    }

    /// The lap's right-click menu: leave it out, or count it again (#554).
    @ViewBuilder private func lapMarkItems(_ lap: LogbookEntry.LapRecord) -> some View {
        if let markLap {
            LapCountsMenu.items(for: lap) { reason in
                Task { markFailed = !(await markLap(lap.number, reason)) }
            }
        }
    }

    private func timeCell(_ lap: LogbookEntry.LapRecord) -> some View {
        let isBest = lap.number == entry.bestLapNumber
        let text = lap.seconds.map { TimeParsing.lapTimeString($0) } ?? "—"
        return Text(text)
            // A lap left out (#554) is still listed, in secondary text.
            .foregroundStyle(isBest ? Color.accentColor : lap.counts ? .primary : .secondary)
            .fontWeight(isBest ? .semibold : nil)
            .accessibilityLabel("Lap \(lap.number) \(text)\(isBest ? ", the best lap" : "")")
            .accessibilityIdentifier("logbook.lap.\(lap.number).time")
    }

    @ViewBuilder private func gapCell(_ lap: LogbookEntry.LapRecord) -> some View {
        if !lap.isComplete {
            Text("partial").foregroundStyle(.secondary)
                .help("Not driven from line to line: the recording began or ended during it")
                .accessibilityIdentifier("logbook.lap.\(lap.number).gap")
        } else if let reason = lap.notCounted {
            // Left out (#554): why, in place of a gap to a best it cannot be.
            Text("left out: \(reason.word)").foregroundStyle(.secondary)
                .help("Left out of the best, optimal and rolling laps, consistency and Trends")
                .accessibilityIdentifier("logbook.lap.\(lap.number).leftOut")
        } else if let gap = entry.gapToBest(lap), lap.number != entry.bestLapNumber {
            Text(String(format: "+%.2f", gap))
                .accessibilityLabel(String(format: "%.2f seconds off the best", gap))
                .accessibilityIdentifier("logbook.lap.\(lap.number).gap")
        } else {
            Text("")
        }
    }

    @ViewBuilder private func sectorCell(_ lap: LogbookEntry.LapRecord, _ index: Int, best: Double?) -> some View {
        let name = SectorLayout.name(of: index)
        let identifier = "logbook.lap.\(lap.number).s\(index + 1)"
        if lap.sectors.indices.contains(index), let time = lap.sectors[index] {
            let isBest = time == best
            let text = Self.sectorText(time)
            Text(text)
                .foregroundStyle(isBest ? Color.accentColor : .primary)
                .fontWeight(isBest ? .semibold : nil)
                .accessibilityLabel("\(name) \(text)\(isBest ? ", the best \(name)" : "")")
                .accessibilityIdentifier(identifier)
        } else {
            Text("—").foregroundStyle(.secondary)
                .help("Lap \(lap.number) did not time \(name)")
                .accessibilityLabel("\(name) not timed")
                .accessibilityIdentifier(identifier)
        }
    }

    private enum SpeedColumn: String {
        case top, min
    }

    @ViewBuilder private func speedCell(
        _ speed: Double?, best: Double?, lap: LogbookEntry.LapRecord, column: SpeedColumn
    ) -> some View {
        if let speed {
            let isBest = lap.isComplete && speed == best
            let value = "\(Int((speed * speedUnit.factorFromMetersPerSecond).rounded()))"
            let label = "\(column == .top ? "Top" : "Lowest") speed \(value) \(speedUnit.symbol)"
            Text(value)
                .foregroundStyle(isBest ? Color.accentColor : .primary)
                .fontWeight(isBest ? .semibold : nil)
                .accessibilityLabel(label + (isBest ? ", the best" : ""))
                .accessibilityIdentifier("logbook.lap.\(lap.number).\(column.rawValue)")
        } else {
            Text("—").foregroundStyle(.secondary).accessibilityLabel("No speed")
        }
    }

    /// "27.43", or "1:02.10" for a sector of a minute or more.
    static func sectorText(_ seconds: Double) -> String {
        seconds < 60 ? String(format: "%.2f", seconds) : TimeParsing.lapTimeString(seconds)
    }
}
