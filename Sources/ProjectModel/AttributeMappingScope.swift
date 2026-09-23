import Foundation

/// Which level of the attribute mapping chain is being edited, and for which input (#192).
///
/// The attribute window's sidebar selects one of these. It is a value of its own rather than an
/// `AttributeMappingLevel` because the input level needs to say *which* input, and because the
/// window remembers it between launches (#200), which needs a form that survives a relaunch.
public enum AttributeMappingScope: Hashable, Sendable {
    /// The global mapping in Settings — every later import follows it.
    case global
    /// This project's deviations from the global mapping.
    case project
    /// One data input's deviations, for when a file is the exception.
    case input(InputID)

    /// The level of the chain this scope writes to.
    public var level: AttributeMappingLevel {
        switch self {
        case .global: .global
        case .project: .project
        case .input: .input
        }
    }

    /// The input this scope is about, when it is about one.
    public var inputID: InputID? {
        if case .input(let id) = self { return id }
        return nil
    }

    /// A string form for window state restoration: `global`, `project` or `input:<UUID>`.
    public var storageValue: String {
        switch self {
        case .global: "global"
        case .project: "project"
        case .input(let id): "input:\(id.rawValue.uuidString)"
        }
    }

    /// Reads `storageValue` back. Anything else is `nil`, so a value written by a later build
    /// falls back to the window's default rather than to a wrong scope.
    public init?(storageValue: String) {
        switch storageValue {
        case "global": self = .global
        case "project": self = .project
        default:
            guard storageValue.hasPrefix("input:"),
                let uuid = UUID(uuidString: String(storageValue.dropFirst("input:".count)))
            else { return nil }
            self = .input(InputID(uuid))
        }
    }
}
