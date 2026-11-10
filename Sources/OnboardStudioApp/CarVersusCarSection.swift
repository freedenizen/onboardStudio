import Charts
import MediaKit
import ProjectModel
import SwiftUI
import TelemetryKit

/// Two cars at the circuit, set against each other (#354): their best laps' corners and speed
/// traces, and a sentence per corner naming the car. Lives at the foot of the Trends view when
/// the logbook has two cars there.
struct CarVersusCarSection: View {
    let entries: [LogbookEntry]
    let circuitKey: String
    let cars: [String]
    @State private var firstCar = ""
    @State private var secondCar = ""
    @State private var comparison: CarVersusCar?
    @State private var loading = false
    @State private var failure: String?
    /// Settings ▸ Units ▸ Speed; with nothing chosen there, the region's (#464).
    @AppStorage(Preferences.speedUnit.key) private var appSpeedUnit = Preferences.speedUnit.unset
    private var speedUnit: SpeedDisplayUnit { (SpeedUnitSetting(rawValue: appSpeedUnit) ?? .automatic).shown() }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Car against car").font(.subheadline.weight(.semibold))
                Spacer()
                Picker("First", selection: $firstCar) { ForEach(cars, id: \.self) { Text($0).tag($0) } }
                    .frame(maxWidth: 180)
                    .accessibilityIdentifier("logbook.cars.first")
                Text("against").foregroundStyle(.secondary)
                Picker("Second", selection: $secondCar) { ForEach(cars, id: \.self) { Text($0).tag($0) } }
                    .frame(maxWidth: 180)
                    .accessibilityIdentifier("logbook.cars.second")
            }
            if loading {
                ProgressView("Reading both cars' best laps…").controlSize(.small)
            } else if let failure {
                Text(failure).foregroundStyle(.secondary)
            } else if let comparison {
                Text(comparison.headline).font(.callout).accessibilityIdentifier("logbook.cars.headline")
                traces(comparison)
                corners(comparison)
            }
        }
        .onAppear { pickDefaults() }
        // The sentences are written in the app's units, so a change of unit reads them again.
        .task(id: firstCar + "|" + secondCar + "|" + appSpeedUnit) { await compare() }
    }

    private func pickDefaults() {
        guard cars.count >= 2, firstCar.isEmpty else { return }
        firstCar = cars[0]
        secondCar = cars[1]
    }

    private func compare() async {
        guard !firstCar.isEmpty, !secondCar.isEmpty, firstCar != secondCar,
            let a = PersonalBests.best(in: entries, circuitKey: circuitKey, car: firstCar),
            let b = PersonalBests.best(in: entries, circuitKey: circuitKey, car: secondCar),
            let first = entries.first(where: { $0.id == a.entryID }),
            let second = entries.first(where: { $0.id == b.entryID })
        else {
            comparison = nil
            failure = firstCar == secondCar && !firstCar.isEmpty ? "Pick two different cars." : nil
            return
        }
        loading = true
        failure = nil
        let (firstCar, secondCar) = (firstCar, secondCar)
        let result = await LogbookModel.shared.carComparison(
            first: first, firstCar: firstCar, second: second, secondCar: secondCar)
        guard !Task.isCancelled else { return }
        comparison = result
        failure = result == nil ? "One of the two sessions' files could not be read." : nil
        loading = false
    }

    private func traces(_ comparison: CarVersusCar) -> some View {
        let traces = comparison.speedTraces()
        return VStack(alignment: .leading, spacing: 4) {
            Chart(traces) { trace in
                LineMark(
                    x: .value("Distance", trace.distance),
                    y: .value("Speed", trace.speed * speedUnit.factorFromMetersPerSecond)
                )
                .foregroundStyle(by: .value("Car", trace.car))
            }
            .chartXAxisLabel("m into the lap")
            .chartYAxisLabel(speedUnit.symbol)
            .frame(height: 160)
            .accessibilityLabel("Speed traces of both cars' best laps")
            .accessibilityValue(comparison.headline)
            .accessibilityIdentifier("logbook.cars.traces")
        }
    }

    private func corners(_ comparison: CarVersusCar) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(comparison.sentences.enumerated()), id: \.offset) { index, sentence in
                Text(sentence).font(.callout)
                    .accessibilityIdentifier("logbook.cars.sentence.\(index + 1)")
            }
            Text("Each car's best lap at this circuit, lined up by position; corners from the second car's lap.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}
