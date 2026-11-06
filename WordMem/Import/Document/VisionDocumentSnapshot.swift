import CoreGraphics
import Foundation

/// Target-independent evidence extracted from a Vision document observation.
/// The snapshot exists so the canonical mapper can be tested without loading
/// the iOS 26 Vision runtime in host unit tests.
struct VisionDocumentSnapshot: Sendable, Equatable {
  var title: VisionTextSnapshot?
  var paragraphs: [VisionTextSnapshot]
  var tables: [VisionTableSnapshot]
  var lists: [VisionListSnapshot]
  var fallbackText: VisionTextSnapshot?

  init(
    title: VisionTextSnapshot? = nil,
    paragraphs: [VisionTextSnapshot] = [],
    tables: [VisionTableSnapshot] = [],
    lists: [VisionListSnapshot] = [],
    fallbackText: VisionTextSnapshot? = nil
  ) {
    self.title = title
    self.paragraphs = paragraphs
    self.tables = tables
    self.lists = lists
    self.fallbackText = fallbackText
  }
}

struct VisionTextSnapshot: Sendable, Equatable {
  var transcript: String
  var lines: [VisionLineSnapshot]
  var confidence: Double
  var boundingBox: CGRect
  var alignment: CanonicalTextAlignment?

  init(
    transcript: String,
    lines: [VisionLineSnapshot] = [],
    confidence: Double = 0,
    boundingBox: CGRect = .zero,
    alignment: CanonicalTextAlignment? = nil
  ) {
    self.transcript = transcript
    self.lines = lines
    self.confidence = confidence
    self.boundingBox = boundingBox
    self.alignment = alignment
  }
}

struct VisionLineSnapshot: Sendable, Equatable {
  var text: String
  var confidence: Double
  var boundingBox: CGRect
  var isTitle: Bool
  var words: [VisionWordSnapshot]

  init(
    text: String,
    confidence: Double = 0,
    boundingBox: CGRect = .zero,
    isTitle: Bool = false,
    words: [VisionWordSnapshot] = []
  ) {
    self.text = text
    self.confidence = confidence
    self.boundingBox = boundingBox
    self.isTitle = isTitle
    self.words = words
  }
}

struct VisionWordSnapshot: Sendable, Equatable {
  var text: String
  var confidence: Double
  var boundingBox: CGRect

  init(text: String, confidence: Double = 0, boundingBox: CGRect = .zero) {
    self.text = text
    self.confidence = confidence
    self.boundingBox = boundingBox
  }
}

struct VisionTableSnapshot: Sendable, Equatable {
  var rows: [[VisionTableCellSnapshot]]
  var boundingBox: CGRect

  init(rows: [[VisionTableCellSnapshot]], boundingBox: CGRect = .zero) {
    self.rows = rows
    self.boundingBox = boundingBox
  }
}

struct VisionTableCellSnapshot: Sendable, Equatable {
  var content: VisionTextSnapshot
  var boundingBox: CGRect

  init(content: VisionTextSnapshot, boundingBox: CGRect = .zero) {
    self.content = content
    self.boundingBox = boundingBox
  }
}

struct VisionListSnapshot: Sendable, Equatable {
  var items: [VisionListItemSnapshot]
  var boundingBox: CGRect

  init(items: [VisionListItemSnapshot], boundingBox: CGRect = .zero) {
    self.items = items
    self.boundingBox = boundingBox
  }
}

struct VisionListItemSnapshot: Sendable, Equatable {
  var marker: String
  var content: VisionTextSnapshot
  var boundingBox: CGRect

  init(
    marker: String,
    content: VisionTextSnapshot,
    boundingBox: CGRect = .zero
  ) {
    self.marker = marker
    self.content = content
    self.boundingBox = boundingBox
  }
}
