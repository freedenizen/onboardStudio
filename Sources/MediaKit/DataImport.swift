import Foundation
import Importers
import ProjectModel
import TelemetryKit

/// Turning a data input's settings into a `TelemetrySession`: the attribute mapping in force for
/// it, the options that mapping becomes, and the lap/sector geometry that goes with them.
extension ProjectCompiler {
    /// #111's chain for one data input: the global mapping from preferences, the project's
    /// deviations from it, and this input's deviations from those.
    ///
    /// The global level is read here rather than deeper down for the same reason `appSpeedUnit` is:
    /// it keeps everything below a pure function of what it is handed, which is what lets a test
    /// pin a mapping without touching the running app's settings.
    static func attributeMappings(for settings: DataInputSettings, in project: Project) -> AttributeMappingResolver {
        AttributeMappingResolver(
            global: AttributeMappingTable(json: UserDefaults.standard.value(for: Preferences.attributeMappings)),
            project: project.settings.attributeMappings,
            input: settings.attributeMappings)
    }

    static func importData(
        at url: URL, settings: DataInputSettings, mappings: AttributeMappingResolver = AttributeMappingResolver()
    ) throws -> TelemetrySession {
        var overrides: [String: ChannelRole] = [:]
        for (column, identifier) in settings.roleOverrides {
            if let role = ChannelRole(identifier: identifier) { overrides[column] = role }
        }
        // #111's chain collapsed into what the builder takes: for every attribute any level has an
        // opinion about, the column it comes from and the unit to read it in. Rows naming an
        // attribute this build does not recognise are skipped rather than guessed at.
        var sourceColumns: [ChannelRole: String] = [:]
        var sourceUnits: [ChannelRole: TelemetryUnit] = [:]
        for identifier in mappings.mappedRoles {
            guard let role = ChannelRole(identifier: identifier) else { continue }
            let mapping = mappings.resolved(identifier)
            if let source = mapping.source { sourceColumns[role] = source }
            if let unit = mapping.sourceUnit { sourceUnits[role] = TelemetryUnit(parsing: unit) }
        }
        let options = SessionBuilder.Options(
            roleOverrides: overrides,
            deriveSpeedFromPosition: settings.deriveSpeedFromPosition,
            deriveHeadingFromPosition: settings.deriveHeadingFromPosition,
            unitOverrides: settings.unitOverrides.mapValues { TelemetryUnit(parsing: $0) },
            sourceColumns: sourceColumns,
            sourceUnits: sourceUnits,
            resampleHertz: settings.resampleHertz,
            smoothingSeconds: settings.smoothingSeconds,
            calculatedFields: settings.calculatedFields.map {
                CalculatedField(name: $0.name, expression: $0.expression, unit: $0.unit)
            },
            finishLine: settings.lapLine.map {
                FinishLine(
                    latitude: $0.latitude, longitude: $0.longitude, headingDegrees: $0.headingDegrees,
                    halfWidthMeters: $0.halfWidthMeters, headingToleranceDegrees: $0.headingToleranceDegrees)
            },
            ignoreFirstCrossings: settings.lapLine?.ignoreFirstCrossings ?? 0,
            sectorMode: sectorMode(settings.sectors),
            cornerLabels: settings.cornerLabels,
            trimStart: settings.trim.start, trimEnd: settings.trim.end)
        if let importerID = settings.importerID {
            guard let importer = FormatDetector.importers.first(where: { type(of: $0).id == importerID }) else {
                throw ImportError.unrecognisedFormat
            }
            return try importer.importSession(at: url, options: options)
        }
        return try FormatDetector.importSession(at: url, options: options)
    }

    /// The project's sector settings as TelemetryKit understands them.
    static func sectorMode(_ spec: SectorSpec) -> SectorMode {
        switch spec.mode {
        case .equalDistance: .equalDistance(count: spec.count)
        case .cornerAware: .cornerAware(count: spec.count)
        case .manual:
            .manual(
                lines: spec.lines.map {
                    FinishLine(
                        latitude: $0.latitude, longitude: $0.longitude, headingDegrees: $0.headingDegrees,
                        halfWidthMeters: $0.halfWidthMeters, headingToleranceDegrees: $0.headingToleranceDegrees)
                })
        }
    }
}
