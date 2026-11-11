import AppKit
import Foundation
import ProjectModel
import RenderKit

// MARK: - Object styles

extension EditorModel {
    // MARK: - Styles

    /// Writes the selected object's look to an `.onboardstyle` file.
    func exportStyle() {
        guard let object = selectedObject else { return }
        guard let url = OpenPanels.chooseStyleDestination(suggestedName: object.label) else { return }
        do {
            try ObjectStyle(object: object).data().write(to: url)
            statusMessage = "Saved style to \(url.lastPathComponent)"
        } catch {
            errorMessage = "\(error)"
        }
    }

    /// Applies an `.onboardstyle` file to the selected object, or adds a new object from it.
    func importStyle() {
        guard let url = OpenPanels.chooseStyle() else { return }
        do {
            let style = try ObjectStyle(data: Data(contentsOf: url))
            apply(style, name: "Import Style")
        } catch {
            errorMessage = "\(error)"
        }
    }

    func copyStyle() {
        guard let object = selectedObject, let data = try? ObjectStyle(object: object).data() else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setData(data, forType: NSPasteboard.PasteboardType(ObjectStyle.pasteboardType))
        pasteboard.setString(String(data: data, encoding: .utf8) ?? "", forType: .string)
    }

    var canPasteStyle: Bool {
        NSPasteboard.general.data(forType: NSPasteboard.PasteboardType(ObjectStyle.pasteboardType)) != nil
    }

    func pasteStyle() {
        guard let data = NSPasteboard.general.data(forType: NSPasteboard.PasteboardType(ObjectStyle.pasteboardType)),
            let style = try? ObjectStyle(data: data)
        else { return }
        apply(style, name: "Paste Style")
    }

    private func apply(_ style: ObjectStyle, name: String) {
        if let object = selectedObject {
            edit(name) { project in
                guard let index = project.displayObjects.firstIndex(where: { $0.id == object.id }) else { return }
                style.apply(to: &project.displayObjects[index])
                if style.kind.needsData,
                    project.input(project.displayObjects[index].inputID ?? InputID())?.kind.isData != true
                {
                    project.displayObjects[index].inputID = project.dataInputs.first?.id
                }
            }
        } else {
            var object = DisplayObject.makeDefault(
                kind: style.kind, inputID: style.kind.needsData ? project.dataInputs.first?.id : nil,
                index: project.displayObjects.count)
            style.apply(to: &object)
            edit(name) { $0.displayObjects.append(object) }
            selectedObjectID = object.id
        }
    }

    func removeInput(_ id: InputID) {
        // The objects stay: they are the overlay, and the file is only what they read (#213).
        edit("Remove Input") { $0.removeInput(id) }
        if selectedInputID == id { selectedInputID = nil }
    }

    func addObject(_ kind: DisplayObjectKind) {
        let dataInput = project.dataInputs.first?.id
        let videoInput = project.videoInputs.first?.id
        var kind = kind
        if case .indicator(let params) = kind {
            // Templates carry no logger-specific channel; bind the light to whatever this input has.
            kind = .indicator(params.adapted(to: channelSummaries(for: dataInput)))
        }
        if case .steeringWheel(let params) = kind {
            kind = .steeringWheel(params.adapted(to: channelSummaries(for: dataInput)))
        }
        // A gauge and a bar *are* a scale, and the template's is written for a percentage. Fit it
        // to what the channel actually reads, now, while the object is being made — never later,
        // when it would be changing a scale somebody chose.
        // A speed is fitted in the unit it will be drawn in (#487): a dial of 0–160 is one in miles
        // per hour, and in km/h the needle stopped at 99 mph.
        let summaries = channelSummaries(for: dataInput)
        let unit = speedUnit(for: DisplayObject(label: "", inputID: dataInput, frame: .full, kind: kind))
        if let params = kind.gaugeParams {
            kind = kind.replacingGaugeParams(params.fitted(to: summaries, speedUnit: unit))
        }
        if case .bar(let params) = kind {
            kind = .bar(params.fitted(to: summaries, speedUnit: unit))
        }
        let object = DisplayObject.makeDefault(
            kind: kind, inputID: kind.needsData ? dataInput : videoInput, index: project.displayObjects.count)
        edit("Add \(kind.typeName)") { $0.displayObjects.append(object) }
        selectedObjectID = object.id
    }

    /// Deletes every selected object that is not locked (#90): a lock guards against the delete
    /// key as much as against the mouse.
    func deleteSelectedObject() {
        // A picture tool hides the overlays; nothing it hides is deleted (#275, #277).
        guard pictureTool == nil else { return }
        let ids = selectedObjectIDs.filter { project.displayObject($0)?.isLocked == false }
        guard !ids.isEmpty else {
            if !selectedObjectIDs.isEmpty { statusMessage = "Locked objects are not deleted. Unlock them first (⌘L)." }
            return
        }
        edit(ids.count == 1 ? "Delete Object" : "Delete Objects") { $0.removeObjects(ids) }
        selectedObjectID = nil
    }

    func moveObject(_ id: DisplayObjectID, frame: UnitRect) {
        setOverridable(id, name: "Move Object") { $0.frame = frame }
    }
}

extension EditorModel {
    /// Identifier, name and value range of every channel in a data input (empty until it loads).
    func channelSummaries(for inputID: InputID?) -> [ChannelSummary] {
        guard let inputID else { return [] }
        return loaded?.channelSummaries[inputID] ?? []
    }

    /// The unit `object` is drawn in, as the renderer resolves it: its own, the project's, the
    /// app's, the file's, the region's.
    func speedUnit(for object: DisplayObject) -> SpeedDisplayUnit {
        let app = SpeedUnitSetting(rawValue: UserDefaults.standard.value(for: Preferences.speedUnit)) ?? .automatic
        return RenderPlanner.unitResolver(
            for: object, in: project, sessions: sessions, appSpeedUnit: app, regionalSpeedUnit: .regional()
        ).speed(object.kind.speedUnit)
    }

    /// After data loads: template objects that name no channel take the one this logger offers,
    /// and a speedometer still on its preset dial is fitted to the file in the unit it shows (#487).
    func bindEmptyChannels() {
        guard let summaries = loaded?.channelSummaries, !summaries.isEmpty else { return }
        var copy = project
        let bound = copy.bindEmptyChannels(summaries)
        let fitted = copy.fitSpeedScales(summaries, unit: speedUnit(for:))
        guard !bound.isEmpty else {
            if !fitted.isEmpty {
                // A dial drawn differently is an edit Undo can take back.
                edit("Fit Speed Scale") { $0 = copy }
            } else if copy != project {
                // The dial already fitted, or was changed by hand: only the note that it was
                // waiting is cleared. Bookkeeping, with no undo step of its own.
                document.apply(nil, name: "Fit Speed Scale") { $0 = copy }
                syncFromDocument()
            }
            return
        }
        edit("Bind Channels") { $0 = copy }
        // Say when a direction was measured rather than assumed, so a wrong guess is visible and
        // can be overridden instead of leaving the user wondering why the wheel turns backwards.
        let measured = summaries.values.flatMap { $0 }.contains { ($0.rightTurnCorrelation ?? 0) < 0 }
        statusMessage =
            "Bound \(bound.joined(separator: ", ")) to the matching channel\(bound.count == 1 ? "" : "s") of the data."
            + (measured
                ? " This logger reports a left turn as positive, so those objects were inverted to match." : "")
    }
}
