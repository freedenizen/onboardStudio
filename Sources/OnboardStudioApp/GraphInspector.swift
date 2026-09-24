import ProjectModel
import SwiftUI
import TelemetryKit

struct GraphInspector: View {
    @Bindable var editor: EditorModel
    let object: DisplayObject
    let params: GraphParams

    var body: some View {
        Section("Graph") {
            CommittingTextField("Caption", text: field(\.label, "Caption"))
            Picker("Horizontal axis", selection: field(\.axis, "Horizontal Axis")) {
                Text("Time").tag(GraphAxis.time)
                Text("Distance").tag(GraphAxis.distance)
                Text("Current lap (distance)").tag(GraphAxis.lap)
                Text("Another channel (X-Y)").tag(GraphAxis.channel)
            }
            if params.axis == .time {
                NumberField("Window (s)", value: field(\.window, "Window"))
            } else if params.axis == .distance {
                NumberField("Window (m)", value: field(\.window, "Window"))
            }
            if params.axis.scrolls {
                // Where now sits across the window: what is to the right of it is still to come.
                SliderField(
                    "Now at", value: field(\.playheadPosition, "Playhead Position"), in: 0...1, step: 0.05,
                    scale: .percent, unit: "%", minimumLabel: "Left", maximumLabel: "Right",
                    identifier: "graph.nowAt"
                )
                .help("Where the current moment sits on the graph; the data to its right is still to come")
                // The edges are a flick of the slider away and any other value can be typed; the
                // middle is the one worth a button (#266).
                HStack {
                    Spacer()
                    Button("Middle") {
                        update("Playhead Position") { $0.playheadPosition = GraphParams.middlePlayheadPosition }
                    }
                    .disabled(params.playheadPosition == GraphParams.middlePlayheadPosition)
                    .help("Put the current moment in the middle: as much still to come as has passed")
                    .accessibilityLabel("Put now in the middle")
                    .accessibilityIdentifier("graph.nowAt.middle")
                }
                Toggle("Line at now", isOn: field(\.showPlayheadLine, "Playhead Line"))
                    .disabled(!params.showCursor)
            } else if params.axis == .channel {
                ChannelPicker(
                    editor: editor, object: object, selection: field(\.xChannel, "Horizontal Channel"),
                    title: "Horizontal channel")
                NumberField("Trail (s)", value: field(\.window, "Trail"))
                OptionalNumberField(
                    "Horizontal min", value: field(\.xMinValue, "Horizontal Minimum"), placeholder: "auto")
                OptionalNumberField(
                    "Horizontal max", value: field(\.xMaxValue, "Horizontal Maximum"), placeholder: "auto")
            } else {
                Toggle("Show best lap as ghost", isOn: field(\.compareBestLap, "Ghost Lap"))
                ColorPicker("Ghost colour", selection: color(\.ghostColor, "Ghost Colour"))
            }
            NumberField(
                "Minimum (blank = auto)",
                value: Binding(
                    get: { params.minValue ?? .nan },
                    set: { v in update("Minimum") { $0.minValue = v.isNaN ? nil : v } }))
            NumberField(
                "Maximum (blank = auto)",
                value: Binding(
                    get: { params.maxValue ?? .nan },
                    set: { v in update("Maximum") { $0.maxValue = v.isNaN ? nil : v } }))
            Toggle(
                "Auto range",
                isOn: Binding(
                    get: { params.minValue == nil && params.maxValue == nil },
                    set: { auto in
                        update("Auto Range") {
                            $0.minValue = auto ? nil : 0
                            $0.maxValue = auto ? nil : 100
                        }
                    }))
            if object.usesSpeedUnitPicker {
                SpeedUnitPicker(editor: editor, object: object, selection: field(\.speedUnit, "Speed Unit"))
            } else {
                DisplayUnitPicker(editor: editor, object: object)
            }
        }
        Section("Series") {
            ForEach(params.series) { series in
                let index = params.series.firstIndex { $0.id == series.id } ?? 0
                HStack {
                    ColorPicker(
                        "",
                        selection: Binding(
                            get: { Color(series.color) },
                            set: { c in update("Series \(index + 1) Colour") { $0.series[index].color = RGBAColor(c) } }
                        )
                    )
                    .labelsHidden()
                    .accessibilityLabel("Series \(index + 1) colour")
                    ChannelPicker(
                        editor: editor, object: object,
                        selection: Binding(
                            get: { series.channel },
                            set: { v in update("Series \(index + 1) Channel") { $0.series[index].channel = v } })
                    )
                    .labelsHidden()
                    .accessibilityLabel("Series \(index + 1) channel")
                    Button {
                        update("Remove Series") { $0.series.removeAll { $0.id == series.id } }
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.borderless)
                    .disabled(params.series.count <= 1)
                    .help("Remove this series")
                    .accessibilityLabel("Remove series \(index + 1)")
                }
                Toggle(
                    "Scale on its own",
                    isOn: Binding(
                        get: { series.usesOwnScale },
                        set: { v in update("Series \(index + 1) Own Scale") { $0.series[index].usesOwnScale = v } })
                )
                .accessibilityIdentifier("graph.ownScale")
                if series.usesOwnScale {
                    OptionalNumberField(
                        "Min",
                        value: Binding(
                            get: { series.minValue },
                            set: { v in update("Series \(index + 1) Minimum") { $0.series[index].minValue = v } }),
                        placeholder: "fit")
                    OptionalNumberField(
                        "Max",
                        value: Binding(
                            get: { series.maxValue },
                            set: { v in update("Series \(index + 1) Maximum") { $0.series[index].maxValue = v } }),
                        placeholder: "fit")
                }
            }
            Text(
                "A series on its own scale fills the plot whatever its numbers are, and is left out "
                    + "of the shared fit — which is how throttle in % and brake pressure in kPa can be "
                    + "read against each other."
            )
            .font(.caption).foregroundStyle(.secondary)
            Button("Add Series") {
                update("Add Series") { $0.series.append(GraphSeries(channel: "rpm", color: .white)) }
            }
            .disabled(params.series.count >= 4)
        }
        Section("Look") {
            Stepper("Grid lines: \(params.gridLines)", value: field(\.gridLines, "Grid Lines"), in: 0...8)
            Toggle("Fill under line", isOn: field(\.fillUnderLine, "Fill Under Line"))
            Toggle("Show cursor", isOn: field(\.showCursor, "Cursor"))
            Toggle("Show labels", isOn: field(\.showLabels, "Labels"))
            ColorPicker("Background", selection: color(\.backgroundColor, "Background Colour"))
            ColorPicker("Grid", selection: color(\.gridColor, "Grid Colour"))
            ColorPicker("Text", selection: color(\.textColor, "Text Colour"))
        }
    }

    func field<T>(_ keyPath: WritableKeyPath<GraphParams, T>, _ name: String) -> Binding<T> {
        Binding(get: { params[keyPath: keyPath] }, set: { v in update(name) { $0[keyPath: keyPath] = v } })
    }

    func color(_ keyPath: WritableKeyPath<GraphParams, RGBAColor>, _ name: String) -> Binding<Color> {
        Binding(
            get: { Color(params[keyPath: keyPath]) }, set: { v in update(name) { $0[keyPath: keyPath] = RGBAColor(v) } }
        )
    }

    func update(_ name: String, _ change: (inout GraphParams) -> Void) {
        var new = params
        change(&new)
        editor.updateObject(object.id, name: "Change \(name)") { $0.kind = .graph(new) }
    }
}
