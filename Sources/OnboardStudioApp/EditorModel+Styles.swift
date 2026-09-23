import AppKit
import Foundation
import ProjectModel

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
        switch kind {
        case .gauge(let params): kind = .gauge(params.fitted(to: channelSummaries(for: dataInput)))
        case .speedometer(let params): kind = .speedometer(params.fitted(to: channelSummaries(for: dataInput)))
        case .tachometer(let params): kind = .tachometer(params.fitted(to: channelSummaries(for: dataInput)))
        default: break
        }
        if case .bar(let params) = kind {
            kind = .bar(params.fitted(to: channelSummaries(for: dataInput)))
        }
        let object = DisplayObject.makeDefault(
            kind: kind, inputID: kind.needsData ? dataInput : videoInput, index: project.displayObjects.count)
        edit("Add \(kind.typeName)") { $0.displayObjects.append(object) }
        selectedObjectID = object.id
    }

    func deleteSelectedObject() {
        guard let id = selectedObjectID else { return }
        edit("Delete Object") { project in
            project.displayObjects.removeAll { $0.id == id }
            project.timeline.prune(keeping: project.displayObjects.map(\.id))
        }
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

    /// After data loads: template objects that name no channel take the one this logger offers.
    func bindEmptyChannels() {
        guard let summaries = loaded?.channelSummaries, !summaries.isEmpty else { return }
        var copy = project
        let bound = copy.bindEmptyChannels(summaries)
        guard !bound.isEmpty else { return }
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
