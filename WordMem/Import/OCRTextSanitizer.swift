import Foundation

enum OCRTextSanitizer {
    static func sanitizedText(from rawText: String) -> String {
        sanitizedLines(from: rawText).joined(separator: "\n")
    }

    static func sanitizedLines(from rawText: String) -> [String] {
        rawText
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !isClock($0) && !isStatusOrNoise($0) }
    }

    private static func isClock(_ line: String) -> Bool {
        line.wholeMatch(of: #/^([01]?\d|2[0-3]):([0-5]\d)(:[0-5]\d)?([ ]?[APap][Mm])?$/#) != nil
    }

    private static func isStatusOrNoise(_ line: String) -> Bool {
        if isNumericOnly(line) || isSymbolOnly(line) { return true }

        let normalized = line.lowercased().filter { $0.isLetter || $0.isNumber }
        let statusTerms = ["5g", "4g", "lte", "wifi"]
        return statusTerms.contains { term in
            guard normalized.hasPrefix(term) else { return false }
            let suffix = normalized.dropFirst(term.count)
            return suffix.isEmpty || suffix == "a" || suffix.allSatisfy(\.isNumber)
        }
    }

    private static func isNumericOnly(_ value: String) -> Bool {
        value.unicodeScalars.allSatisfy { scalar in
            CharacterSet.decimalDigits.union(.whitespaces).union(CharacterSet(charactersIn: "%")).contains(scalar)
        }
    }

    private static func isSymbolOnly(_ value: String) -> Bool {
        value.unicodeScalars.allSatisfy { !CharacterSet.alphanumerics.union(.whitespaces).contains($0) }
    }
}
