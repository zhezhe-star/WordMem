import Foundation

/// Turns Vision line output into compact paragraphs suitable for reading and
/// for persistent import context. Formatting is deterministic and offline.
enum OCRTextFormatter {
    static func formattedText(from rawText: String) -> String {
        let lines = OCRTextSanitizer
            .sanitizedLines(from: rawText)
            .compactMap(cleanLine)

        var paragraphs: [String] = []
        var current: [String] = []

        for line in lines {
            if let last = current.last, shouldJoin(last, with: line) {
                current[current.count - 1] = joinLine(last, with: line)
            } else {
                if let paragraph = current.last {
                    paragraphs.append(paragraph)
                }
                current = [line]
            }
        }

        if let paragraph = current.last {
            paragraphs.append(paragraph)
        }

        return paragraphs
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
    }

    private static func cleanLine(_ line: String) -> String? {
        let withoutURL = line.replacingOccurrences(
            of: #"https?://\S+"#,
            with: "",
            options: [.regularExpression]
        )
        let readable = String(withoutURL.unicodeScalars.filter { isReadable($0) })
            .replacingOccurrences(of: #"\s+"#, with: " ", options: [.regularExpression])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return readable.isEmpty ? nil : readable
    }

    private static func isReadable(_ scalar: Unicode.Scalar) -> Bool {
        CharacterSet.alphanumerics.union(.whitespaces).union(.punctuationCharacters).contains(scalar)
            || "’‘“”–—…".contains(Character(scalar))
    }

    private static func shouldJoin(_ current: String, with next: String) -> Bool {
        guard !isListItem(next) else { return false }
        if current.hasSuffix("-") { return true }
        return !current.hasSuffix(".")
            && !current.hasSuffix("!")
            && !current.hasSuffix("?")
    }

    private static func joinLine(_ current: String, with next: String) -> String {
        if current.hasSuffix("-") {
            return String(current.dropLast()) + next
        }
        return current + " " + next
    }

    private static func isListItem(_ line: String) -> Bool {
        line.wholeMatch(of: /^[•·▪]\s+.+/) != nil
    }
}
