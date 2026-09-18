import CoreGraphics
import Foundation
import JavaScriptCore
import ProjectModel
import RenderKit

/// Owns one JavaScript context for one scripted object. Compiles the prelude and the user
/// script once, then runs `background` / `frame`. Never throws: problems are recorded in
/// `error` and the caller draws a badge instead. All access is serialised by `lock`.
public final class ScriptEngine: @unchecked Sendable {
    public struct Problem: Equatable, Sendable {
        public let message: String
        /// 1-based line in the user's script when known.
        public let line: Int?
    }

    private let lock = NSLock()
    private let context: JSContext
    private let canvas = CanvasBridge()
    private let data = DataBridge()
    private var backgroundFunction: JSValue?
    private var frameFunction: JSValue?
    private var problem: Problem?
    private var frameCount = 0
    private var frameSeconds = 0.0

    public init(source: String) {
        context = JSContext()
        context.name = "OverlayGen script"
        setUp(source: source)
    }

    /// The last error, or `nil` when the script is healthy.
    public var error: Problem? {
        lock.lock()
        defer { lock.unlock() }
        return problem
    }

    /// Average seconds spent per `frame` call so far (for the budget test and the inspector).
    public var averageFrameSeconds: Double {
        lock.lock()
        defer { lock.unlock() }
        return frameCount > 0 ? frameSeconds / Double(frameCount) : 0
    }

    public var hasBackground: Bool {
        lock.lock()
        defer { lock.unlock() }
        return backgroundFunction != nil
    }

    private func setUp(source: String) {
        context.exceptionHandler = { [weak self] _, exception in
            self?.record(exception)
        }
        context.setObject(canvas, forKeyedSubscript: "canvas" as NSString)
        context.setObject(data, forKeyedSubscript: "data" as NSString)
        let log: @convention(block) (String) -> Void = { _ in }
        context.setObject(["log": log] as [String: Any], forKeyedSubscript: "console" as NSString)
        context.evaluateScript(ScriptPrelude.source, withSourceURL: URL(fileURLWithPath: "/prelude.js"))
        // A syntax error in the prelude would be ours, not the user's; scripts start at line 1.
        problem = nil
        context.evaluateScript(source, withSourceURL: URL(fileURLWithPath: "/script.js"))
        guard problem == nil else { return }
        let background = context.objectForKeyedSubscript("background")
        let frame = context.objectForKeyedSubscript("frame")
        backgroundFunction = background?.isUndefined == false ? background : nil
        frameFunction = frame?.isUndefined == false ? frame : nil
        if frameFunction == nil && backgroundFunction == nil {
            problem = Problem(message: "Define frame(canvas, data) and/or background(canvas).", line: nil)
        }
    }

    private func record(_ exception: JSValue?) {
        guard let exception else { return }
        let message = exception.toString() ?? "Script error"
        var line: Int?
        if let raw = exception.objectForKeyedSubscript("line"), raw.isNumber { line = Int(raw.toInt32()) }
        if let url = exception.objectForKeyedSubscript("sourceURL")?.toString(), url.hasSuffix("prelude.js") {
            line = nil
        }
        // Keep the first problem; later ones are usually consequences of it.
        if problem == nil { problem = Problem(message: message, line: line) }
    }

    /// Checks a script without rendering: syntax or setup errors only.
    public static func check(_ source: String) -> Problem? {
        ScriptEngine(source: source).error
    }

    // MARK: - Running

    /// Runs `background(canvas)` into `cg` (top-left origin, `size` pixels).
    public func drawBackground(into cg: CGContext, size: CGSize) {
        lock.lock()
        defer { lock.unlock() }
        guard let backgroundFunction, problem == nil else { return }
        canvas.begin(context: cg, width: size.width, height: size.height, time: 0)
        context.objectForKeyedSubscript("__rrBind")?.call(withArguments: [canvas, data])
        backgroundFunction.call(withArguments: [canvas])
        canvas.end()
    }

    /// Runs `frame(canvas, data)` into `cg` for project `time`.
    public func drawFrame(into cg: CGContext, size: CGSize, time: Double, objectContext: ObjectContext) {
        lock.lock()
        defer { lock.unlock() }
        guard let frameFunction, problem == nil else { return }
        let started = DispatchTime.now().uptimeNanoseconds
        data.begin(context: objectContext, time: time)
        canvas.begin(context: cg, width: size.width, height: size.height, time: time)
        context.objectForKeyedSubscript("__rrBind")?.call(withArguments: [canvas, data])
        frameFunction.call(withArguments: [canvas, data])
        canvas.end()
        frameSeconds += Double(DispatchTime.now().uptimeNanoseconds - started) / 1e9
        frameCount += 1
    }

    /// Evaluates an expression and returns its string form; for tests and the console.
    public func evaluate(_ expression: String) -> String? {
        lock.lock()
        defer { lock.unlock() }
        return context.evaluateScript(expression)?.toString()
    }
}
