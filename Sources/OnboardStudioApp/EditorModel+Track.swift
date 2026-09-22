import AppKit
import Foundation
import ProjectModel
import RenderKit
import TelemetryKit

// MARK: - The start/finish line, and track definitions as files

extension EditorModel {
    /// Uses the start/finish and sector gates a file carried, for a file just added that has no
    /// line of its own yet (#71). Returns whether it had any.
    ///
    /// Only for a file *being added*: opening a saved project must keep the line it was saved
    /// with, whatever the file says.
    @discardableResult
    func applyLapGeometry(of session: TelemetrySession, to id: InputID) -> Bool {
        guard let start = session.lapGeometry.start else { return false }
        guard case .data(let existing)? = project.input(id)?.kind, existing.lapLine == nil else { return false }
        let splits = session.lapGeometry.splits
        updateInput(id, name: "Use the File's Start/Finish") {
            guard case .data(var settings) = $0.kind else { return }
            settings.lapLine = Self.lapLine(from: start)
            if !splits.isEmpty {
                settings.sectors = SectorSpec(
                    mode: .manual, count: splits.count + 1, lines: splits.map(Self.lapLine(from:)))
            }
            $0.kind = .data(settings)
        }
        let sectors = splits.isEmpty ? "" : " and \(splits.count + 1) sectors"
        statusMessage = "Used the start/finish line\(sectors) this file was recorded with."
        return true
    }

    /// A gate as the lap detector wants it: the middle of the line, and how far it reaches either
    /// side. The heading is deliberately left unset — a gate says where the line is and not which
    /// way the car crosses it, and the two perpendiculars are equally consistent with it.
    static func lapLine(from gate: LapGate) -> LapLineSpec {
        LapLineSpec(
            latitude: gate.centreLatitude, longitude: gate.centreLongitude,
            halfWidthMeters: gate.halfWidthMeters)
    }

    /// Offers the line the data itself suggests, so a session opens with something workable rather
    /// than with nothing.
    ///
    /// The driver corrects a proposal instead of authoring one from scratch, which is the whole
    /// point: the trace already shows where the laps repeat.
    ///
    /// Returns whether there was anything to suggest, so a caller can say so in its own words.
    @discardableResult
    func suggestStartFinish(for id: InputID) -> Bool {
        guard let session = sessions[id] else { return false }
        guard let suggestion = StartFinishFinder.suggest(in: session) else {
            statusMessage = "Nothing in this file looks like a lap, so there is no line to suggest."
            return false
        }
        let line = suggestion.line
        updateInput(id, name: "Suggest Start/Finish") {
            guard case .data(var settings) = $0.kind else { return }
            settings.lapLine = LapLineSpec(
                latitude: line.latitude, longitude: line.longitude, headingDegrees: line.headingDegrees,
                halfWidthMeters: line.halfWidthMeters,
                headingToleranceDegrees: line.headingToleranceDegrees,
                ignoreFirstCrossings: settings.lapLine?.ignoreFirstCrossings ?? 0)
            $0.kind = .data(settings)
        }
        statusMessage = suggestion.summary
        return true
    }

    /// Writes this input's circuit, line, sectors and corner names to a file to hand to someone.
    func exportTrackDefinition(for id: InputID) {
        guard let definition = trackDefinition(for: id) else { return }
        guard let url = OpenPanels.chooseTrackDestination(suggestedName: definition.name) else { return }
        do {
            try TrackLibrary.write(definition, to: url)
            statusMessage = "Exported \(definition.name)."
        } catch {
            statusMessage = "Could not export the track: \(error.localizedDescription)"
        }
    }

    /// Reads someone else's definition and applies it to this input, keeping it for next time.
    ///
    /// Applying on the spot is right here and wrong in `applyPendingTrackDefinition`: choosing a
    /// file from a panel is the driver asking for this project to change, where merely opening a
    /// saved project is not.
    func importTrackDefinition(for id: InputID) {
        guard let url = OpenPanels.chooseTrack() else { return }
        let definition: TrackDefinition
        do {
            definition = try TrackLibrary.read(from: url)
        } catch {
            statusMessage = "Could not read that track definition: \(error.localizedDescription)"
            return
        }
        updateInput(id, name: "Import Track Definition") {
            guard case .data(var settings) = $0.kind else { return }
            if let circuitID = definition.circuitID { settings.circuitID = circuitID }
            if let line = definition.startFinish { settings.lapLine = line }
            settings.sectors = definition.sectors
            settings.cornerLabels = definition.cornerLabels
            $0.kind = .data(settings)
        }
        try? trackLibrary.save(definition)
        statusMessage = "Imported \(definition.name) and kept it for next time."
    }

    /// What would be saved or exported for this input: the circuit if one is known, otherwise the
    /// place the file was recorded.
    ///
    /// A club circuit, an airfield or a car park is not in the bundled list and never will be, and
    /// a definition for one is exactly as worth sharing as a definition for Silverstone.
    func trackDefinition(for id: InputID) -> TrackDefinition? {
        guard case .data(let settings) = project.input(id)?.kind else { return nil }
        if let match = circuit(for: id) {
            return TrackDefinition(
                circuitID: match.circuit.id, name: match.circuit.name, latitude: match.circuit.latitude,
                longitude: match.circuit.longitude, startFinish: settings.lapLine, sectors: settings.sectors,
                cornerLabels: settings.cornerLabels)
        }
        guard let session = sessions[id], let latitude = session[.latitude]?.values.first,
            let longitude = session[.longitude]?.values.first
        else { return nil }
        return TrackDefinition(
            name: project.input(id)?.label ?? "Track", latitude: latitude, longitude: longitude,
            startFinish: settings.lapLine, sectors: settings.sectors, cornerLabels: settings.cornerLabels)
    }

    // MARK: - Placing the line on the map

    /// The map object the line is placed on, the projection it was drawn with, and the line itself.
    ///
    /// `nil` whenever the gesture cannot mean anything — nothing being edited, no line yet, or no
    /// track map on screen to point at.
    var startFinishTarget: StartFinishTarget? {
        // Only while this input is the one being looked at, or the mode would stay on with no
        // control anywhere on screen to turn it off again.
        guard let id = startFinishEditing, id == selectedInputID, let session = sessions[id] else { return nil }
        guard case .data(let settings) = project.input(id)?.kind, let line = settings.lapLine else { return nil }
        // It has to be a map of *this* input's trace. A map bound to another input is somewhere
        // else entirely, and a map bound to none draws nothing at all to point at.
        guard
            let object = resolvedObjects.first(where: {
                guard case .trackMap = $0.kind else { return false }
                return $0.isVisible && $0.inputID == id
            })
        else { return nil }
        guard case .trackMap(let params) = object.kind,
            let projection = projection(of: session, params: params, for: id)
        else { return nil }
        return StartFinishTarget(input: id, object: object, projection: projection, line: line)
    }

    /// The map's projection, built once per set of map options rather than once per redraw.
    ///
    /// `startFinishTarget` is read on every SwiftUI update, and building a projection walks the
    /// whole trace — tens of thousands of samples on a track day — which is not a thing to do
    /// sixty times a second while the video plays underneath it.
    private func projection(of session: TelemetrySession, params: TrackMapParams, for id: InputID)
        -> TrackProjection?
    {
        let key = MapProjectionKey(input: id, params: params, samples: session[.latitude]?.count ?? 0)
        if let cached = cachedProjection, cached.key == key { return cached.projection }
        guard let built = TrackProjection(session: session, params: params) else { return nil }
        cachedProjection = (key, built)
        return built
    }

    /// Records where a drag on the map left the line.
    func placeStartFinish(_ line: LapLineSpec, for id: InputID) {
        updateInput(id, name: "Place Start/Finish") {
            guard case .data(var settings) = $0.kind else { return }
            settings.lapLine = line
            $0.kind = .data(settings)
        }
    }
}

/// What a cached map projection was built for. The sample count stands in for the session: a
/// reload that changes the trace changes it, and comparing whole channels every redraw would cost
/// more than rebuilding.
struct MapProjectionKey: Equatable {
    let input: InputID
    let params: TrackMapParams
    let samples: Int
}

/// Everything the preview needs to draw and drag a start/finish line, gathered once.
struct StartFinishTarget {
    let input: InputID
    let object: DisplayObject
    let projection: TrackProjection
    let line: LapLineSpec
}

extension StartFinishFinder.Suggestion {
    /// How the suggestion is explained: where it came from and how well it held up, because a line
    /// the app proposed has to be checked, not trusted.
    var summary: String {
        let origin = source == .fileLaps ? "the lap numbers in the file" : "where the trace repeats"
        return String(
            format: "Suggested a start/finish from %@: %d laps, within %.1f%%.", origin, laps, spread * 100)
    }
}
