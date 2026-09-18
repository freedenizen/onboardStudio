import Foundation

/// A tiny arithmetic expression language for calculated fields:
/// numbers, channel references (`speed`, `rpm`, `[aux:Oil temp]`), `+ - * / %`, unary minus,
/// comparisons (`< <= > >= == !=` → 1 or 0), `&& || !`, parentheses, and functions
/// `abs min max sqrt pow floor ceil round clamp if(cond, a, b)`.
public struct Expression: Sendable, Hashable {
    indirect enum Node: Sendable, Hashable {
        case number(Double)
        case channel(String)
        case unary(String, Node)
        case binary(String, Node, Node)
        case call(String, [Node])
    }

    let root: Node
    public let source: String
    /// Channel identifiers referenced by the expression.
    public let references: [String]

    public init(_ source: String) throws {
        self.source = source
        var parser = Parser(tokens: try Tokenizer.tokenize(source))
        root = try parser.parseExpression()
        guard parser.isAtEnd else { throw ExpressionError.unexpectedToken(parser.peek?.text ?? "end") }
        var refs: [String] = []
        Self.collect(root, into: &refs)
        references = refs
    }

    private static func collect(_ node: Node, into refs: inout [String]) {
        switch node {
        case .number: break
        case .channel(let name): if !refs.contains(name) { refs.append(name) }
        case .unary(_, let a): collect(a, into: &refs)
        case .binary(_, let a, let b):
            collect(a, into: &refs)
            collect(b, into: &refs)
        case .call(_, let args): args.forEach { collect($0, into: &refs) }
        }
    }

    /// Evaluates with `lookup` supplying channel values; a missing channel yields `nil`.
    public func evaluate(_ lookup: (String) -> Double?) -> Double? {
        Self.eval(root, lookup)
    }

    private static func eval(_ node: Node, _ lookup: (String) -> Double?) -> Double? {
        switch node {
        case .number(let v): return v
        case .channel(let name): return lookup(name)
        case .unary(let op, let a):
            guard let x = eval(a, lookup) else { return nil }
            return op == "-" ? -x : (x == 0 ? 1 : 0)
        case .binary(let op, let a, let b):
            guard let x = eval(a, lookup), let y = eval(b, lookup) else { return nil }
            return binary(op, x, y)
        case .call(let name, let args):
            return call(name, args, lookup)
        }
    }

    private static func call(_ name: String, _ args: [Node], _ lookup: (String) -> Double?) -> Double? {
        if name == "if", args.count == 3 {
            guard let cond = eval(args[0], lookup) else { return nil }
            return eval(cond != 0 ? args[1] : args[2], lookup)
        }
        let values = args.map { eval($0, lookup) }
        guard !values.contains(where: { $0 == nil }) else { return nil }
        let v = values.compactMap { $0 }
        switch (name, v.count) {
        case ("abs", 1): return abs(v[0])
        case ("sqrt", 1): return v[0] < 0 ? nil : sqrt(v[0])
        case ("floor", 1): return floor(v[0])
        case ("ceil", 1): return ceil(v[0])
        case ("round", 1): return v[0].rounded()
        case ("min", _) where !v.isEmpty: return v.min()
        case ("max", _) where !v.isEmpty: return v.max()
        case ("pow", 2): return pow(v[0], v[1])
        case ("clamp", 3): return min(max(v[0], v[1]), v[2])
        default: return nil
        }
    }

    private static func binary(_ op: String, _ x: Double, _ y: Double) -> Double? {
        switch op {
        case "+": x + y
        case "-": x - y
        case "*": x * y
        case "/": y == 0 ? nil : x / y
        case "%": y == 0 ? nil : x.truncatingRemainder(dividingBy: y)
        case "<": x < y ? 1 : 0
        case "<=": x <= y ? 1 : 0
        case ">": x > y ? 1 : 0
        case ">=": x >= y ? 1 : 0
        case "==": x == y ? 1 : 0
        case "!=": x != y ? 1 : 0
        case "&&": (x != 0 && y != 0) ? 1 : 0
        case "||": (x != 0 || y != 0) ? 1 : 0
        default: nil
        }
    }

    // MARK: - Tokens

    typealias Token = ExpressionToken

    enum Tokenizer {
        static func tokenize(_ text: String) throws -> [Token] {
            var tokens: [Token] = []
            let chars = Array(text)
            var i = 0
            while i < chars.count {
                let c = chars[i]
                if c.isWhitespace {
                    i += 1
                } else if c.isNumber || (c == "." && i + 1 < chars.count && chars[i + 1].isNumber) {
                    i = scan(chars, from: i, into: &tokens, kind: .number) { $0.isNumber || $0 == "." }
                } else if c == "[" {
                    guard let close = chars[i...].firstIndex(of: "]") else { throw ExpressionError.unterminatedBracket }
                    tokens.append(Token(kind: .identifier, text: String(chars[(i + 1)..<close])))
                    i = close + 1
                } else if c.isLetter || c == "_" {
                    i = scan(chars, from: i, into: &tokens, kind: .identifier) {
                        $0.isLetter || $0.isNumber || $0 == "_" || $0 == ":"
                    }
                } else if let punctuation = punctuationKind(c) {
                    tokens.append(Token(kind: punctuation, text: String(c)))
                    i += 1
                } else {
                    i = try scanOperator(chars, from: i, into: &tokens)
                }
            }
            return tokens
        }

        private static func scan(
            _ chars: [Character], from start: Int, into tokens: inout [Token], kind: Token.Kind,
            while accept: (Character) -> Bool
        ) -> Int {
            var j = start
            while j < chars.count, accept(chars[j]) { j += 1 }
            tokens.append(Token(kind: kind, text: String(chars[start..<j])))
            return j
        }

        private static func punctuationKind(_ c: Character) -> Token.Kind? {
            switch c {
            case "(": .lparen
            case ")": .rparen
            case ",": .comma
            default: nil
            }
        }

        private static func scanOperator(_ chars: [Character], from i: Int, into tokens: inout [Token]) throws -> Int {
            let two = i + 1 < chars.count ? String(chars[i...(i + 1)]) : ""
            if ["<=", ">=", "==", "!=", "&&", "||"].contains(two) {
                tokens.append(Token(kind: .op, text: two))
                return i + 2
            }
            let c = chars[i]
            guard "+-*/%<>!".contains(c) else { throw ExpressionError.unexpectedCharacter(String(c)) }
            tokens.append(Token(kind: .op, text: String(c)))
            return i + 1
        }
    }

    // MARK: - Parser (precedence climbing)

    struct Parser {
        let tokens: [Token]
        var index = 0

        init(tokens: [Token]) { self.tokens = tokens }

        var peek: Token? { index < tokens.count ? tokens[index] : nil }
        var isAtEnd: Bool { index >= tokens.count }

        mutating func advance() -> Token? {
            defer { index += 1 }
            return peek
        }

        static let precedence: [String: Int] = [
            "||": 1, "&&": 2, "==": 3, "!=": 3, "<": 4, "<=": 4, ">": 4, ">=": 4, "+": 5, "-": 5, "*": 6, "/": 6,
            "%": 6,
        ]

        mutating func parseExpression(minPrecedence: Int = 1) throws -> Node {
            var left = try parseUnary()
            while let token = peek, token.kind == .op, let prec = Self.precedence[token.text], prec >= minPrecedence {
                index += 1
                let right = try parseExpression(minPrecedence: prec + 1)
                left = .binary(token.text, left, right)
            }
            return left
        }

        mutating func parseUnary() throws -> Node {
            if let token = peek, token.kind == .op, token.text == "-" || token.text == "!" {
                index += 1
                return .unary(token.text, try parseUnary())
            }
            return try parsePrimary()
        }

        mutating func parsePrimary() throws -> Node {
            guard let token = advance() else { throw ExpressionError.unexpectedEnd }
            switch token.kind {
            case .number:
                guard let value = Double(token.text) else { throw ExpressionError.badNumber(token.text) }
                return .number(value)
            case .identifier:
                if peek?.kind == .lparen {
                    index += 1
                    var args: [Node] = []
                    if peek?.kind != .rparen {
                        repeat {
                            args.append(try parseExpression())
                            if peek?.kind == .comma { index += 1 } else { break }
                        } while true
                    }
                    guard advance()?.kind == .rparen else { throw ExpressionError.expected(")") }
                    return .call(token.text.lowercased(), args)
                }
                return .channel(token.text)
            case .lparen:
                let inner = try parseExpression()
                guard advance()?.kind == .rparen else { throw ExpressionError.expected(")") }
                return inner
            default:
                throw ExpressionError.unexpectedToken(token.text)
            }
        }
    }
}

struct ExpressionToken: Equatable {
    enum Kind { case number, identifier, op, lparen, rparen, comma }
    let kind: Kind
    let text: String
}

public enum ExpressionError: Error, Equatable, CustomStringConvertible {
    case unexpectedCharacter(String)
    case unexpectedToken(String)
    case unexpectedEnd
    case unterminatedBracket
    case badNumber(String)
    case expected(String)

    public var description: String {
        switch self {
        case .unexpectedCharacter(let c): "Unexpected character '\(c)'."
        case .unexpectedToken(let t): "Unexpected '\(t)'."
        case .unexpectedEnd: "Unexpected end of expression."
        case .unterminatedBracket: "Missing ']' after a channel name."
        case .badNumber(let n): "'\(n)' is not a number."
        case .expected(let e): "Expected '\(e)'."
        }
    }
}

/// A user-defined channel computed from other channels at every sample of the primary channel.
public struct CalculatedField: Sendable, Hashable, Codable {
    public var name: String
    public var expression: String
    public var unit: String

    public init(name: String, expression: String, unit: String = "") {
        self.name = name
        self.expression = expression
        self.unit = unit
    }
}

extension TelemetrySession {
    /// Adds an `aux:<name>` channel evaluated on the union of referenced channels' sample times
    /// (falling back to the speed or first channel's axis). Throws for bad expressions.
    public mutating func addCalculatedField(_ field: CalculatedField) throws {
        let expression = try Expression(field.expression)
        let referenced = expression.references.compactMap { ChannelRole(identifier: $0).flatMap { self[$0] } }
        guard let axis = referenced.first ?? self[.speed] ?? orderedChannels.first else { return }
        let sampler = TelemetrySampler(session: self)
        var times: [Double] = []
        var values: [Double] = []
        for t in axis.times {
            let sample = sampler.sample(at: t)
            let value = expression.evaluate { identifier in
                ChannelRole(identifier: identifier).flatMap { sample[$0] }
            }
            if let value, value.isFinite {
                times.append(t)
                values.append(value)
            }
        }
        guard !times.isEmpty else { return }
        add(
            Channel(
                role: .aux(field.name), name: field.name, unit: TelemetryUnit(parsing: field.unit), times: times,
                values: values))
    }
}
