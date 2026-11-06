import CryptoKit
import Foundation

/// Builds a deterministic canonical structure from typed or pasted text.
///
/// Text parsing is intentionally rule-based so the first pipeline stage can
/// run locally, offline, and without Foundation Models. Block text is already
/// normalized; span offsets are therefore measured against canonical text.
struct TextDocumentCanonicalizer: Sendable {
    func canonicalize(_ text: String, origin: CanonicalOrigin) -> CanonicalDocument {
        let lines = Self.normalizedLines(from: text)
        let blocks = Self.parseBlocks(from: lines)
        let documentID = Self.deterministicID(seed: "canonical-document\n\(origin.rawValue)\n\(lines.joined(separator: "\n"))")

        return CanonicalDocument(
            id: documentID,
            origin: origin,
            detectedLanguage: nil,
            blocks: blocks
        )
    }

    private static func normalizedLines(from text: String) -> [String] {
        let newlineNormalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\u{FEFF}", with: "")
            .replacingOccurrences(of: "\u{200B}", with: "")
            .replacingOccurrences(of: "\u{00A0}", with: " ")

        return newlineNormalized
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { line in
                String(line.unicodeScalars.filter { scalar in
                    scalar == "\n" || !((0...0x1F).contains(scalar.value) && scalar != "\t")
                })
                .replacingOccurrences(
                    of: #"[ \t]+$"#,
                    with: "",
                    options: .regularExpression
                )
            }
    }

    private static func parseBlocks(from lines: [String]) -> [CanonicalBlock] {
        var blocks: [CanonicalBlock] = []
        var paragraphLines: [String] = []

        func flushParagraph() {
            guard !paragraphLines.isEmpty else { return }
            let text = paragraphLines.joined(separator: "\n")
            append(kind: .paragraph, text: text, to: &blocks)
            paragraphLines = []
        }

        var index = 0
        while index < lines.count {
            let line = lines[index]
            let structuralLine = line.trimmingCharacters(in: .whitespaces)

            if structuralLine.isEmpty {
                flushParagraph()
                index += 1
                continue
            }

            if isFence(structuralLine) {
                flushParagraph()
                let code = collectCode(from: lines, startingAt: index)
                append(kind: .code, text: code.text, to: &blocks)
                index = code.nextIndex
                continue
            }

            if let heading = markerContent(in: structuralLine, afterPrefixes: ["# ", "## ", "### ", "#### ", "##### ", "###### "]) {
                flushParagraph()
                append(kind: .heading, text: heading, to: &blocks)
                index += 1
                continue
            }

            if let listItem = listContent(in: structuralLine) {
                flushParagraph()
                append(kind: .listItem, text: listItem, to: &blocks)
                index += 1
                continue
            }

            if let quote = markerContent(in: structuralLine, afterPrefixes: ["> "]) {
                flushParagraph()
                append(kind: .quote, text: quote, to: &blocks)
                index += 1
                continue
            }

            paragraphLines.append(line)
            index += 1
        }

        flushParagraph()
        return blocks
    }

    private static func isFence(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~")
    }

    private static func collectCode(from lines: [String], startingAt startIndex: Int) -> (text: String, nextIndex: Int) {
        let contentLines = lines[(startIndex + 1)...].prefix { !isFence($0) }
        let text = contentLines.joined(separator: "\n")
        let nextIndex = startIndex + 1 + contentLines.count
        let hasClosingFence = nextIndex < lines.count && isFence(lines[nextIndex])
        return (text, hasClosingFence ? nextIndex + 1 : nextIndex)
    }

    private static func markerContent(in line: String, afterPrefixes prefixes: [String]) -> String? {
        let prefix = prefixes.first { line.hasPrefix($0) }
        return prefix.map { String(line.dropFirst($0.count)) }
    }

    private static func listContent(in line: String) -> String? {
        guard let markerEnd = listMarkerEnd(in: line) else { return nil }
        return String(line[markerEnd...])
    }

    private static func listMarkerEnd(in line: String) -> String.Index? {
        var index = line.startIndex

        while index < line.endIndex, line[index].isWhitespace {
            index = line.index(after: index)
        }
        guard index < line.endIndex else { return nil }

        let markerCharacter = line[index]
        if markerCharacter == "-" || markerCharacter == "*" || markerCharacter == "+" {
            let nextIndex = line.index(after: index)
            return nextIndex < line.endIndex && line[nextIndex].isWhitespace ? line.index(after: nextIndex) : nil
        }

        guard markerCharacter.isNumber else { return nil }
        var numberEnd = index
        var numberCount = 0
        while numberEnd < line.endIndex, line[numberEnd].isNumber, numberCount < 9 {
            numberEnd = line.index(after: numberEnd)
            numberCount += 1
        }
        guard numberEnd < line.endIndex, line[numberEnd] == "." || line[numberEnd] == ")" else { return nil }
        let spaceIndex = line.index(after: numberEnd)
        return spaceIndex < line.endIndex && line[spaceIndex].isWhitespace ? line.index(after: spaceIndex) : nil
    }

    private static func append(kind: CanonicalBlockKind, text: String, to blocks: inout [CanonicalBlock]) {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return }

        let order = blocks.count
        let blockID = deterministicID(seed: "canonical-block\n\(kind.rawValue)\n\(order)")
        let spanID = deterministicID(seed: "canonical-span\n\(blockID.uuidString)")
        let spanEnd = trimmedText.utf16.count
        let span = CanonicalSpan(
            id: spanID,
            text: trimmedText,
            charRange: 0..<spanEnd,
            confidence: 1,
            geometry: nil
        )
        blocks.append(
            CanonicalBlock(
                id: blockID,
                order: order,
                kind: kind,
                text: trimmedText,
                spans: [span],
                geometry: nil,
                confidence: 1
            )
        )
    }

    private static func deterministicID(seed: String) -> UUID {
        let digest = SHA256.hash(data: Data(seed.utf8))
        var bytes = Array(digest.prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x40
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }
}
