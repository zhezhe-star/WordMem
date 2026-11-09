import CryptoKit
import Foundation

/// A deterministic, read-only projection of canonical content.
///
/// Markdown-flavored markers make document structure scannable during review,
/// but this format is not persistence or storage. Canonical blocks remain the
/// source of truth and import submissions keep their existing payload shape.
enum CanonicalReviewProjection {
  static func formattedText(for document: CanonicalDocument) -> String {
    var lines: [String] = []
    var listItems: [String] = []
    var index = 0

    while index < document.blocks.count {
      let block = document.blocks[index]

      if block.kind != .listItem {
        flushListItems(&listItems, into: &lines)
      }

      switch block.kind {
      case .list:
        // Canonical image documents retain both a list container and its
        // children. Rendering the container itself would duplicate every
        // item, so children own their projected bullets.
        index += 1
        continue

      case .listItem:
        append("- \(block.text)", to: &listItems)

      case .table:
        append(tableRows(from: block.text), to: &lines)

      case .tableCell:
        // A table container already carries every cell in reading order.
        index += 1
        continue

      case .title:
        append("# \(block.text)", to: &lines)

      case .heading:
        append("## \(block.text)", to: &lines)

      case .code:
        append("```\n\(block.text)\n```", to: &lines)

      case .quote:
        append("> \(block.text)", to: &lines)

      case .paragraph, .caption:
        append(block.text, to: &lines)
      }

      index += 1
    }

    flushListItems(&listItems, into: &lines)
    return lines.joined(separator: "\n\n")
  }

  private static func append(_ line: String, to lines: inout [String]) {
    let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedLine.isEmpty else { return }
    lines.append(trimmedLine)
  }

  private static func flushListItems(
    _ listItems: inout [String],
    into lines: inout [String]
  ) {
    guard !listItems.isEmpty else { return }
    lines.append(listItems.joined(separator: "\n"))
    listItems.removeAll()
  }

  private static func append(_ lines: [String], to output: inout [String]) {
    let compactLines = lines.filter { !$0.isEmpty }
    guard !compactLines.isEmpty else { return }
    output.append(compactLines.joined(separator: "\n"))
  }

  private static func tableRows(from canonicalText: String) -> [String] {
    canonicalText
      .components(separatedBy: .newlines)
      .map { row in
        "| " + row.components(separatedBy: "\t").joined(separator: " | ") + " |"
      }
  }
}

/// Stable identifiers for derived review documents. Derivation never changes
/// canonical evidence; a deterministic ID only makes tests repeatable.
enum DeterministicReviewIdentifier {
  static func uuid(seed: String) -> UUID {
    let digest = SHA256.hash(data: Data(seed.utf8))
    let digestBytes = Array(digest)
    let hex = digestBytes.prefix(16).map {
      String(format: "%02x", $0)
    }.joined()

    return UUID(
      uuidString: [
        hex.prefix(8),
        hex.dropFirst(8).prefix(4),
        hex.dropFirst(12).prefix(4),
        hex.dropFirst(16).prefix(4),
        hex.dropFirst(20).prefix(12),
      ].map(String.init).joined(separator: "-"))!
  }
}
