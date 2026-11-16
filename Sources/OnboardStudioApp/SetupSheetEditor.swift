import ProjectModel
import SwiftUI

/// A session's or a day's setup sheet (#559): the tyres, pressures at each corner, alignment,
/// dampers, bars and wing, every one optional; setups the car keeps, to load or save; and which of
/// them a new session in the car starts with. Nothing is written until Done, as one step of Undo.
struct SetupSheetEditor: View {
    /// What the sheet is of: "Session 3, 14 Nov 2026".
    let subject: String
    let car: String
    let conditions: SessionConditions
    /// The Logbook window's: a sheet's own environment has none of its own to take the steps.
    let undoManager: UndoManager?
    let save: (SessionConditions) -> Void
    @Environment(\.dismiss) private var dismiss
    @AppStorage(Preferences.setupPressureUnit.key) private var pressureChoice = ""
    @State private var texts: [SetupItem: String] = [:]
    @State private var name = ""
    @State private var tyres = ""
    @State private var toeUnit = SetupSheet.ToeUnit.millimeters
    @State private var loaded = false

    private var model: LogbookModel { .shared }
    private var units: SetupUnits { Self.units(choice: pressureChoice) }
    private var garageCar: Car? { Garage.car(named: car, in: model.cars) }
    private var saved: [SavedSetup] { garageCar?.setups ?? [] }
    /// The car's setup of the name typed, if it keeps one.
    private var savedNamed: SavedSetup? {
        let typed = name.trimmingCharacters(in: .whitespaces)
        return saved.first { Garage.same($0.name, typed) }
    }
    private var invalid: [SetupItem] {
        SetupItem.all.filter { item in
            var sheet = SetupSheet()
            return !item.set(texts[item] ?? "", in: &sheet, units: units)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Setup").font(.title2)
            Text("\(subject). Note as much or as little as you like: every value is optional.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            savedSetupRow
            Divider()
            SetupTyresSection(texts: $texts, tyres: $tyres, pressureChoice: $pressureChoice, units: units)
            Divider()
            SetupChassisSection(texts: $texts, toeUnit: $toeUnit, units: units)
            footer
        }
        .padding(20)
        .frame(width: 640)
        .onAppear(perform: load)
        .onChange(of: pressureChoice) { old, new in
            convertPressures(from: Self.units(choice: old), to: Self.units(choice: new))
        }
    }

    // MARK: - Saved setups

    private var savedSetupRow: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
            GridRow {
                Text("Name").foregroundStyle(.secondary)
                HStack {
                    TextField("Base, Wet, Soft Rear Bar…", text: $name)
                        .accessibilityIdentifier("setup.name")
                    Menu("Saved Setups") {
                        if saved.isEmpty { Text("No Setups Saved for This Car") }
                        ForEach(saved) { setup in
                            Button(setup.name) { load(setup) }
                        }
                        if !saved.isEmpty {
                            Divider()
                            Menu("Delete Setup") {
                                ForEach(saved) { setup in
                                    Button(setup.name, role: .destructive) {
                                        model.deleteSetup(setup, forCar: car, undo: undoManager)
                                    }
                                }
                            }
                        }
                    }
                    .fixedSize()
                    .disabled(car.isEmpty)
                    .help(
                        car.isEmpty
                            ? "Setups are kept with a car: name the car first" : "Load a setup kept with the \(car)"
                    )
                    .accessibilityIdentifier("setup.saved")
                    Button(savedNamed == nil ? "Save to Car" : "Update Saved Setup", action: saveToCar)
                        .disabled(car.isEmpty || name.trimmingCharacters(in: .whitespaces).isEmpty || !invalid.isEmpty)
                        .help(saveHelp)
                        .accessibilityIdentifier("setup.saveToCar")
                }
            }
            if let savedNamed, !car.isEmpty {
                GridRow {
                    Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                    Toggle("Start new sessions in the \(car) with this setup", isOn: startingBinding(savedNamed))
                        .accessibilityIdentifier("setup.starting")
                }
            }
        }
        .font(.callout)
    }

    private var saveHelp: String {
        if car.isEmpty { return "Setups are kept with a car: name the car first" }
        if name.trimmingCharacters(in: .whitespaces).isEmpty { return "Name the setup to keep it with the car" }
        return savedNamed == nil
            ? "Keep this setup with the \(car), to load onto another session"
            : "Replace the \(car)'s “\(savedNamed?.name ?? "")” with these values"
    }

    private func startingBinding(_ setup: SavedSetup) -> Binding<Bool> {
        Binding(
            get: { garageCar?.startingSetupID == setup.id },
            set: { model.setStartingSetup($0 ? setup.id : nil, forCar: car, undo: undoManager) })
    }

    private func saveToCar() {
        guard let sheet = built() else { return }
        let setup = SavedSetup(
            id: savedNamed?.id ?? UUID(), name: name, tyres: tyres.trimmingCharacters(in: .whitespaces), sheet: sheet)
        name = model.saveSetup(setup, forCar: car, undo: undoManager).name
    }

    // MARK: - Done and Cancel

    private var footer: some View {
        HStack {
            if !invalid.isEmpty {
                Label(
                    "Not a number: \(invalid.map(\.title).joined(separator: ", "))",
                    systemImage: "exclamationmark.triangle"
                )
                .font(.callout).foregroundStyle(.secondary).lineLimit(2)
                .accessibilityIdentifier("setup.invalid")
            }
            Spacer()
            Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                .accessibilityIdentifier("setup.cancel")
            Button("Done", action: commit).keyboardShortcut(.defaultAction)
                .disabled(!invalid.isEmpty)
                .accessibilityIdentifier("setup.done")
        }
    }

    private func commit() {
        guard let sheet = built() else { return }
        var changed = conditions
        changed.tyres = tyres.trimmingCharacters(in: .whitespaces)
        changed.sheet = sheet
        if changed != conditions { save(changed) }
        dismiss()
    }

    // MARK: - Fields

    static func units(choice: String) -> SetupUnits {
        var units = SetupUnits.app
        if let pressure = SetupUnits.Pressure(rawValue: choice) { units.pressure = pressure }
        return units
    }

    /// The sheet the fields say, or `nil` while one of them is not a number.
    private func built() -> SetupSheet? {
        var sheet = SetupSheet(name: name.trimmingCharacters(in: .whitespaces), toeUnit: toeUnit)
        for item in SetupItem.all where !item.set(texts[item] ?? "", in: &sheet, units: units) { return nil }
        return sheet
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        tyres = conditions.tyres
        fill(from: conditions.sheet)
    }

    private func load(_ setup: SavedSetup) {
        if !setup.tyres.isEmpty { tyres = setup.tyres }
        fill(from: setup.sheet)
        name = setup.name
    }

    private func fill(from sheet: SetupSheet) {
        name = sheet.name
        toeUnit = sheet.toeUnit
        texts = Dictionary(uniqueKeysWithValues: SetupItem.all.map { ($0, $0.editText(in: sheet, units: units)) })
    }

    /// The pressures typed, shown again in the unit just chosen.
    private func convertPressures(from old: SetupUnits, to new: SetupUnits) {
        for item in SetupItem.all {
            switch item {
            case .coldPressure, .hotPressure, .bled:
                var sheet = SetupSheet()
                guard item.set(texts[item] ?? "", in: &sheet, units: old) else { continue }
                texts[item] = item.editText(in: sheet, units: new)
            default: continue
            }
        }
    }
}
