import CoreGraphics
import Foundation

/// The normalized, source-independent representation used by the document
/// import pipeline. Canonical documents are immutable once created.
struct CanonicalDocument: Identifiable, Codable, Hashable, Sendable {
  let id: UUID
  let origin: CanonicalOrigin
  let detectedLanguage: Locale.Language?
  let blocks: [CanonicalBlock]
}

extension CanonicalDocument {
  /// Selects the semantic units sent to document translation.
  ///
  /// Structured containers remain canonical evidence but are not their own
  /// translation units when usable children are present. Blocks are already
  /// in reading order, so a container consumes the adjacent run of children
  /// it owns; an unrenderable child is omitted in favor of usable siblings.
  var translationUnitBlocks: [CanonicalBlock] {
    var units: [CanonicalBlock] = []
    var index = 0

    while index < blocks.count {
      let block = blocks[index]
      guard let childKind = block.kind.translationChildKind else {
        units.append(block)
        index += 1
        continue
      }

      var usableChildren: [CanonicalBlock] = []
      var childIndex = index + 1
      while childIndex < blocks.count, blocks[childIndex].kind == childKind {
        if !blocks[childIndex].text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
          usableChildren.append(blocks[childIndex])
        }
        childIndex += 1
      }

      if usableChildren.isEmpty {
        units.append(block)
      } else {
        units.append(contentsOf: usableChildren)
      }
      index = childIndex
    }

    return units
  }
}

extension CanonicalBlockKind {
  fileprivate var translationChildKind: CanonicalBlockKind? {
    switch self {
    case .list: .listItem
    case .table: .tableCell
    default: nil
    }
  }
}

/// The input surface that produced a canonical document.
enum CanonicalOrigin: String, Codable, Sendable {
  case typedText
  case pastedText
  case image
  case shareExtension
  case translationProvider
}

/// One semantically meaningful region of a canonical document.
struct CanonicalBlock: Identifiable, Codable, Hashable, Sendable {
  let id: UUID
  let order: Int
  let kind: CanonicalBlockKind
  let text: String
  let spans: [CanonicalSpan]
  let geometry: CanonicalGeometry?
  let confidence: Double
}

/// The deterministic block categories supported by the canonical foundation.
enum CanonicalBlockKind: String, Codable, Sendable {
  case title
  case heading
  case paragraph
  case list
  case listItem
  case table
  case tableCell
  case code
  case caption
  case quote
}

/// A text run within its owning block. Character ranges use UTF-16 offsets,
/// matching Foundation and TextKit string-index conventions.
struct CanonicalSpan: Identifiable, Codable, Hashable, Sendable {
  let id: UUID
  let text: String
  let charRange: Range<Int>
  let confidence: Double
  let geometry: CanonicalGeometry?
}

/// Optional source geometry retained without coupling canonical text to UIKit.
struct CanonicalGeometry: Codable, Hashable, Sendable {
  let normalizedBoundingBox: CGRect
  let readingOrderHint: Int?
  let alignment: CanonicalTextAlignment?
}

/// Text alignment evidence for source geometry.
enum CanonicalTextAlignment: String, Codable, Sendable {
  case left
  case center
  case right
  case justified
}
