import Foundation

/// Setups kept with a car (#559): saved from a session's sheet, loaded onto another, and one of
/// them the car's starting setup, which a new session in the car takes when it has none.
extension Logbook {
    /// Keeps `setup` with `car`: in place of the setup with its id, or with its name (a setup saved
    /// again under a name the car already uses replaces that one), else as a new one. A car named
    /// for the first time joins the garage with it. Returns the setup as kept.
    @discardableResult
    public func saveSetup(_ setup: SavedSetup, forCar name: String) throws -> SavedSetup {
        let car = name.trimmingCharacters(in: .whitespaces)
        var kept = setup
        kept.name = setup.name.trimmingCharacters(in: .whitespaces)
        kept.sheet.name = kept.name
        guard !car.isEmpty, !kept.name.isEmpty else { return setup }
        var cars = cars()
        let index =
            cars.firstIndex { Garage.same($0.name, car) }
            ?? {
                cars.append(Car(name: car))
                return cars.count - 1
            }()
        if let same = cars[index].setups.firstIndex(where: { $0.id == kept.id }) {
            cars[index].setups[same] = kept
        } else if let named = cars[index].setups.firstIndex(where: { Garage.same($0.name, kept.name) }) {
            kept.id = cars[index].setups[named].id
            cars[index].setups[named] = kept
        } else {
            cars[index].setups.append(kept)
        }
        try saveCars(cars)
        return kept
    }

    /// Takes the setup out of the car; a session it was loaded onto keeps its values and its name.
    public func deleteSetup(_ id: UUID, forCar name: String) throws {
        var cars = cars()
        guard let index = cars.firstIndex(where: { Garage.same($0.name, name) }),
            cars[index].setups.contains(where: { $0.id == id })
        else { return }
        cars[index].setups.removeAll { $0.id == id }
        if cars[index].startingSetupID == id { cars[index].startingSetupID = nil }
        try saveCars(cars)
    }

    /// Makes the setup the car's starting setup, or none with `nil`.
    public func setStartingSetup(_ id: UUID?, forCar name: String) throws {
        var cars = cars()
        guard let index = cars.firstIndex(where: { Garage.same($0.name, name) }), cars[index].startingSetupID != id,
            id.map({ id in cars[index].setups.contains { $0.id == id } }) ?? true
        else { return }
        cars[index].startingSetupID = id
        try saveCars(cars)
    }

    /// The car's starting setup on `conditions`, when they note no tyres and no setup of their own.
    public func applyStartingSetup(to conditions: inout SessionConditions, car: String) {
        guard conditions.hasNoSetup, !car.trimmingCharacters(in: .whitespaces).isEmpty,
            let starting = Garage.car(named: car, in: cars())?.startingSetup
        else { return }
        conditions.load(starting)
    }
}

extension Logbook {
    /// The driver's scale on the car's learned grip (#558), kept between half and twice it.
    public func setGripAdjustment(_ factor: Double, forCar name: String) throws {
        let car = name.trimmingCharacters(in: .whitespaces)
        guard !car.isEmpty, factor.isFinite else { return }
        let kept = min(max(factor, 0.5), 2)
        var cars = cars()
        if let index = cars.firstIndex(where: { Garage.same($0.name, car) }) {
            guard cars[index].gripAdjustment != kept else { return }
            cars[index].gripAdjustment = kept
        } else {
            cars.append(Car(name: car, gripAdjustment: kept))
        }
        try saveCars(cars)
    }

    /// The limit `entry` is read against: its car's, in its conditions, as the driver adjusted it.
    public func gripLimit(for entry: LogbookEntry, among entries: [LogbookEntry]? = nil) -> CarGripLimit? {
        let adjustment = Garage.car(named: entry.car, in: cars())?.gripAdjustment ?? 1
        return CarGrip.limit(for: entry, among: entries ?? self.entries(), adjustment: adjustment)
    }
}
