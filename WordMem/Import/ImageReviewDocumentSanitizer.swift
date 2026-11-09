import CoreGraphics
import Foundation

/// Removes screenshot chrome only from the review copy used for translation,
/// semantic display, and candidate extraction.
///
/// The input canonical document is never mutated, so Vision evidence and the
/// original image remain intact for later diagnosis and persistence.
enum ImageReviewDocumentSanitizer {
  static func reviewDocument(from document: CanonicalDocument) -> CanonicalDocument {
    let projectedBlocks = projectedBlocks(from: document.blocks)
    let projectedText = projectedBlocks.map(\.text).joined(separator: "\n")

    return CanonicalDocument(
      id: DeterministicReviewIdentifier.uuid(
        seed: "image-review-document\n\(document.id.uuidString)\n\(projectedText)"
      ),
      origin: document.origin,
      detectedLanguage: document.detectedLanguage,
      blocks: projectedBlocks
    )
  }

  private static func projectedBlocks(from blocks: [CanonicalBlock]) -> [CanonicalBlock] {
    var projected: [CanonicalBlock] = []
    var index = 0

    while index < blocks.count {
      let block = blocks[index]

      switch block.kind {
      case .list:
        let (children, nextIndex) = childBlocks(
          kind: .listItem,
          after: index + 1,
          in: blocks
        )
        if let projectedContainer = projectedListContainer(block, children: children) {
          projected.append(projectedContainer)
        }
        index = nextIndex

      case .table:
        let childResult = childBlocks(
          kind: .tableCell,
          after: index + 1,
          in: blocks
        )
        if let projectedContainer = projectedTableContainer(block) {
          projected.append(projectedContainer)
        }
        index = childResult.nextIndex

      case .listItem, .tableCell:
        // Orphaned canonical children are handled with their container.
        index += 1

      default:
        if let projectedBlock = projectedTextBlock(block) {
          projected.append(projectedBlock)
        }
        index += 1
      }
    }

    return projected
  }

  private static func childBlocks(
    kind: CanonicalBlockKind,
    after startIndex: Int,
    in blocks: [CanonicalBlock]
  ) -> (children: [CanonicalBlock], nextIndex: Int) {
    var children: [CanonicalBlock] = []
    var index = startIndex

    while index < blocks.count, blocks[index].kind == kind {
      children.append(blocks[index])
      index += 1
    }

    return (children, index)
  }

  private static func projectedListContainer(
    _ container: CanonicalBlock,
    children: [CanonicalBlock]
  ) -> CanonicalBlock? {
    let retainedItems = children.compactMap(projectedTextBlock).map(\.text)
    guard !retainedItems.isEmpty else { return nil }
    return makingBlock(container, text: retainedItems.joined(separator: "\n"))
  }

  private static func projectedTableContainer(
    _ container: CanonicalBlock
  ) -> CanonicalBlock? {
    let retainedRows = container.text
      .components(separatedBy: .newlines)
      .compactMap(projectedTableRow)
    guard !retainedRows.isEmpty else { return nil }
    return makingBlock(container, text: retainedRows.joined(separator: "\n"))
  }

  private static func projectedTableRow(from row: String) -> String? {
    let retainedCells =
      row
      .components(separatedBy: "\t")
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !isObviousNoise($0, blockKind: .tableCell, isTopRegion: false) }
    guard retainedCells.contains(where: { !$0.isEmpty }) else { return nil }
    return retainedCells.joined(separator: "\t")
  }

  private static func projectedTextBlock(_ block: CanonicalBlock) -> CanonicalBlock? {
    let isTopRegion = (block.geometry?.normalizedBoundingBox.minY ?? 1) <= 0.15
    let retainedLines = block.text
      .components(separatedBy: .newlines)
      .filter { !isObviousNoise($0, blockKind: block.kind, isTopRegion: isTopRegion) }
    let projectedText =
      retainedLines
      .joined(separator: "\n")
      .trimmingCharacters(in: .whitespacesAndNewlines)
    guard !projectedText.isEmpty else { return nil }
    return makingBlock(block, text: projectedText)
  }

  private static func makingBlock(
    _ block: CanonicalBlock,
    text: String
  ) -> CanonicalBlock {
    CanonicalBlock(
      id: DeterministicReviewIdentifier.uuid(
        seed: "image-review-block\n\(block.id.uuidString)\n\(text)"
      ),
      order: block.order,
      kind: block.kind,
      text: text,
      spans: block.spans,
      geometry: block.geometry,
      confidence: block.confidence
    )
  }

  static func isObviousNoise(
    _ text: String,
    blockKind: CanonicalBlockKind,
    isTopRegion: Bool
  ) -> Bool {
    let line = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !line.isEmpty else { return true }

    if clockOnly(line) || numericOrSymbolOnly(line) || urlOnly(line) {
      return true
    }

    return isTopRegion
      && blockKind != .title
      && line.count <= 32
      && isShortNonTitleChrome(line)
  }

  private static func clockOnly(_ line: String) -> Bool {
    line.range(
      of: #"^(?:0?\d|1\d|2[0-3])(?::[0-5]\d)\s*(?:am|pm|AM|PM)?$"#,
      options: .regularExpression
    ) != nil
  }

  private static func numericOrSymbolOnly(_ line: String) -> Bool {
    line.range(
      of: #"^[0-9\s\p{P}\p{S}%+°]+$"#,
      options: .regularExpression
    ) != nil
  }

  private static func urlOnly(_ line: String) -> Bool {
    line.range(
      of: #"^(?:https?://|www\.)\S+$"#,
      options: .regularExpression
    ) != nil
  }

  private static func isShortNonTitleChrome(_ line: String) -> Bool {
    let lowercased = line.lowercased()
    let chromeTerms = [
      "carrier", "wifi", "wi-fi", "battery", "bluetooth", "lte", "search",
      "reload", "cancel", "done", "share", "settings", "keyboard",
    ]
    if chromeTerms.contains(where: lowercased.contains) {
      return true
    }

    // A short top line is chrome only when it lacks substantive words. This
    // keeps titles such as "Chapter 1" and other meaningful short headings.
    let substantiveWords =
      line
      .components(separatedBy: CharacterSet.whitespacesAndPunctuationCharacters)
      .filter { $0.count >= 4 && $0.rangeOfCharacter(from: .letters) != nil }
    return substantiveWords.isEmpty
  }
}

extension CharacterSet {
  fileprivate static let whitespacesAndPunctuationCharacters = CharacterSet(
    charactersIn: " \t\r\n"
  )
  .union(.punctuationCharacters)
  .union(.symbols)
}
