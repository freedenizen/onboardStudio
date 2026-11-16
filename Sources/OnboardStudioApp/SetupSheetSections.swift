import ProjectModel
import SwiftUI

/// One value of a setup sheet, typed: a narrow field named for VoiceOver by what it is.
struct SetupField: View {
    let item: SetupItem
    @Binding var texts: [SetupItem: String]
    var width: CGFloat = 64

    var body: some View {
        TextField("", text: Binding(get: { texts[item] ?? "" }, set: { texts[item] = $0 }))
            .multilineTextAlignment(.trailing)
            .frame(width: width)
            .accessibilityLabel(item.title)
            .accessibilityIdentifier("setup.\(item.title)")
    }
}

/// The tyre set and its pressures at each corner: cold, hot, and how much was let out.
struct SetupTyresSection: View {
    @Binding var texts: [SetupItem: String]
    @Binding var tyres: String
    @Binding var pressureChoice: String
    let units: SetupUnits

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Tyres").font(.headline)
                Spacer()
                Picker("Pressures in", selection: pressureUnit) {
                    ForEach(SetupUnits.Pressure.allCases, id: \.self) { Text($0.symbol).tag($0) }
                }
                .fixedSize()
                .accessibilityIdentifier("setup.pressureUnit")
            }
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                GridRow {
                    Text("Set").foregroundStyle(.secondary)
                    TextField("Compound, age, which set", text: $tyres)
                        .gridCellColumns(4)
                        .accessibilityIdentifier("setup.tyres")
                }
                CornerHeader()
                cornerRow("Cold (\(units.pressure.symbol))", SetupItem.coldPressure)
                cornerRow("Hot (\(units.pressure.symbol))", SetupItem.hotPressure)
                cornerRow("Bled (\(units.pressure.symbol))", SetupItem.bled)
            }
            .font(.callout)
        }
    }

    private var pressureUnit: Binding<SetupUnits.Pressure> {
        Binding(get: { units.pressure }, set: { pressureChoice = $0.rawValue })
    }

    private func cornerRow(_ title: String, _ item: @escaping (SetupItem.Corner) -> SetupItem) -> some View {
        GridRow {
            Text(title).foregroundStyle(.secondary)
            ForEach(SetupItem.Corner.allCases, id: \.self) { SetupField(item: item($0), texts: $texts) }
        }
    }
}

/// Column titles for the four corners.
struct CornerHeader: View {
    var body: some View {
        GridRow {
            Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
            ForEach(SetupItem.Corner.allCases, id: \.self) { corner in
                Text(corner.title).font(.caption).foregroundStyle(.secondary)
                    .frame(width: 64, alignment: .trailing)
            }
        }
    }
}

/// Camber at each corner; toe, ride height, dampers and bars at each end; the wing.
struct SetupChassisSection: View {
    @Binding var texts: [SetupItem: String]
    @Binding var toeUnit: SetupSheet.ToeUnit
    let units: SetupUnits

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Chassis").font(.headline)
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                CornerHeader()
                GridRow {
                    Text("Camber (°)").foregroundStyle(.secondary)
                    ForEach(SetupItem.Corner.allCases, id: \.self) { SetupField(item: .camber($0), texts: $texts) }
                }
                GridRow {
                    Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                    Text("Front").font(.caption).foregroundStyle(.secondary).gridCellColumns(2)
                    Text("Rear").font(.caption).foregroundStyle(.secondary).gridCellColumns(2)
                }
                GridRow {
                    HStack(spacing: 4) {
                        Text("Toe").foregroundStyle(.secondary)
                        Picker("Toe in", selection: $toeUnit) {
                            ForEach(SetupSheet.ToeUnit.allCases, id: \.self) { Text($0.symbol).tag($0) }
                        }
                        .labelsHidden().fixedSize()
                        .accessibilityLabel("Toe Unit")
                        .accessibilityIdentifier("setup.toeUnit")
                    }
                    axleFields(SetupItem.toe)
                }
                axleRow("Ride height (\(units.length.symbol))", SetupItem.rideHeight)
                axleRow("Bump (clicks)", SetupItem.bump)
                axleRow("Rebound (clicks)", SetupItem.rebound)
                axleRow("Anti-roll bar", SetupItem.antiRollBar, width: 140)
                GridRow {
                    Text("Wing").foregroundStyle(.secondary)
                    SetupField(item: .wing, texts: $texts, width: 292).gridCellColumns(4)
                }
            }
            .font(.callout)
        }
    }

    private func axleRow(_ title: String, _ item: @escaping (SetupItem.Axle) -> SetupItem, width: CGFloat = 64)
        -> some View
    {
        GridRow {
            Text(title).foregroundStyle(.secondary)
            axleFields(item, width: width)
        }
    }

    @ViewBuilder
    private func axleFields(_ item: @escaping (SetupItem.Axle) -> SetupItem, width: CGFloat = 64) -> some View {
        ForEach(SetupItem.Axle.allCases, id: \.self) { axle in
            SetupField(item: item(axle), texts: $texts, width: width).gridCellColumns(2)
        }
    }
}
