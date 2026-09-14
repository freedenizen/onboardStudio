import Foundation

/// A minimal, dependency-free delimited-text reader that handles quoted fields, embedded
/// delimiters, doubled quotes, CR/LF/CRLF line endings, a UTF-8 BOM, and automatic detection of
/// comma / semicolon / tab delimiters.
public struct CSVReader: Sendable {
    public enum Delimiter: Character, Sendable, CaseIterable {
        case comma = ","
        case semicolon = ";"
        case tab = "\t"
    }

    public let delimiter: Delimiter

    public init(delimiter: Delimiter) {
        self.delimiter = delimiter
    }

    /// Picks the delimiter that yields the most consistent field count across the first lines.
    public static func detectDelimiter(in text: Substring, sampleLines: Int = 20) -> Delimiter {
        let lines = text.split(omittingEmptySubsequences: true, whereSeparator: \.isNewline).prefix(sampleLines)
        var best: (Delimiter, Int) = (.comma, 0)
        for candidate in Delimiter.allCases {
            let counts = lines.map { $0.filter { $0 == candidate.rawValue }.count }
            let score = counts.reduce(0, +)
            if score > best.1 { best = (candidate, score) }
        }
        return best.0
    }

    /// Splits one physical line into fields. Quotes are stripped and doubled quotes unescaped.
    public func fields(of line: Substring) -> [String] {
        var result: [String] = []
        var current = ""
        var inQuotes = false
        var iterator = line.makeIterator()
        var pending: Character? = iterator.next()
        while let character = pending {
            pending = iterator.next()
            if inQuotes {
                if character == "\"" {
                    if pending == "\"" {
                        current.append("\"")
                        pending = iterator.next()
                    } else {
                        inQuotes = false
                    }
                } else {
                    current.append(character)
                }
            } else if character == "\"" {
                inQuotes = true
            } else if character == delimiter.rawValue {
                result.append(current)
                current = ""
            } else {
                current.append(character)
            }
        }
        result.append(current)
        return result
    }

    /// Splits text into lines, tolerating any line-ending style and dropping a trailing empty line.
    public static func lines(of text: Substring) -> [Substring] {
        var lines = text.split(
            omittingEmptySubsequences: false, whereSeparator: { $0 == "\n" || $0 == "\r\n" || $0 == "\r" })
        if lines.last?.isEmpty == true { lines.removeLast() }
        return lines
    }

    /// Reads a whole file as text, stripping a UTF-8 BOM and trying UTF-8 then Latin-1.
    public static func loadText(from url: URL) throws -> String {
        let data = try Data(contentsOf: url)
        var text: String
        if let utf8 = String(data: data, encoding: .utf8) {
            text = utf8
        } else if let latin1 = String(data: data, encoding: .isoLatin1) {
            text = latin1
        } else {
            throw ImportError.unreadableText
        }
        if text.hasPrefix("\u{FEFF}") { text.removeFirst() }
        return text
    }

    /// Parses a numeric cell, accepting a European decimal comma. Empty or non-numeric → `nil`.
    public static func number(_ field: String) -> Double? {
        let trimmed = field.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return nil }
        if let value = Double(trimmed) { return value }
        if trimmed.contains(",") && !trimmed.contains(".") {
            return Double(trimmed.replacingOccurrences(of: ",", with: "."))
        }
        return nil
    }
}
