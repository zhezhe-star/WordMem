import CryptoKit
import Foundation
import UIKit
import Vision

/// The replaceable Vision boundary consumed by the image import flow.
protocol ImageDocumentRecognitionService: Sendable {
  func recognizeDocument(in imageData: Data) async throws -> CanonicalDocument
}

struct VisionDocumentReader: ImageDocumentRecognitionService {
  private let observationProvider: any VisionDocumentObservationProviding

  init(
    observationProvider: any VisionDocumentObservationProviding =
      SystemVisionDocumentObservationProvider()
  ) {
    self.observationProvider = observationProvider
  }

  func recognizeDocument(in imageData: Data) async throws -> CanonicalDocument {
    guard let image = UIImage(data: imageData), let cgImage = image.cgImage else {
      throw WordImageImportError.invalidImageData
    }

    let snapshots = try await observationProvider.snapshots(
      from: cgImage,
      orientation: image.imageOrientation.visionOrientation
    )
    guard let snapshot = snapshots.first(where: { !$0.isEmpty }) else {
      throw WordImageImportError.noRecognizedText
    }

    let document = VisionDocumentCanonicalMapper.canonicalDocument(from: snapshot)
    guard !document.blocks.isEmpty else {
      throw WordImageImportError.noRecognizedText
    }
    return document
  }
}

protocol VisionDocumentObservationProviding: Sendable {
  func snapshots(
    from cgImage: CGImage,
    orientation: CGImagePropertyOrientation
  ) async throws -> [VisionDocumentSnapshot]
}

@available(iOS 26.0, *)
struct SystemVisionDocumentObservationProvider: VisionDocumentObservationProviding {
  func snapshots(
    from cgImage: CGImage,
    orientation: CGImagePropertyOrientation
  ) async throws -> [VisionDocumentSnapshot] {
    var request = RecognizeDocumentsRequest()
    request.textRecognitionOptions.useLanguageCorrection = true

    let observations = try await request.perform(on: cgImage, orientation: orientation)
    return observations.map { observation in
      VisionDocumentSnapshotFactory.snapshot(from: observation)
    }
  }
}

@available(iOS 26.0, *)
private enum VisionDocumentSnapshotFactory {
  static func snapshot(from observation: DocumentObservation) -> VisionDocumentSnapshot {
    let container = observation.document

    return VisionDocumentSnapshot(
      title: container.title.map { text(from: $0) },
      paragraphs: container.paragraphs.map { text(from: $0) },
      tables: container.tables.map(table(from:)),
      lists: container.lists.map(list(from:)),
      fallbackText: container.paragraphs.isEmpty && container.tables.isEmpty
        && container.lists.isEmpty ? text(from: container.text) : nil
    )
  }

  private static func table(from table: DocumentObservation.Container.Table) -> VisionTableSnapshot
  {
    VisionTableSnapshot(
      rows: table.rows.map { row in
        row.map { cell in
          VisionTableCellSnapshot(
            content: text(from: cell.content.text),
            boundingBox: normalizedBoundingBox(
              from: cell.content.boundingRegion.boundingBox.cgRect
            )
          )
        }
      },
      boundingBox: normalizedBoundingBox(from: table.boundingRegion.boundingBox.cgRect)
    )
  }

  private static func list(from list: DocumentObservation.Container.List) -> VisionListSnapshot {
    VisionListSnapshot(
      items: list.items.map { item in
        VisionListItemSnapshot(
          marker: item.markerString,
          content: text(from: item.content.text),
          boundingBox: normalizedBoundingBox(
            from: item.content.boundingRegion.boundingBox.cgRect
          )
        )
      },
      boundingBox: normalizedBoundingBox(from: list.boundingRegion.boundingBox.cgRect)
    )
  }

  private static func text(from text: DocumentObservation.Container.Text) -> VisionTextSnapshot {
    let lines = text.lines.map { line in
      VisionLineSnapshot(
        text: line.transcript,
        confidence: Double(line.confidence),
        boundingBox: normalizedBoundingBox(
          from: line.boundingRegion.boundingBox.cgRect
        ),
        isTitle: line.isTitle,
        words: []
      )
    }

    var usedLines = lines
    assign(text.words ?? [], to: &usedLines)

    return VisionTextSnapshot(
      transcript: usedLines.map(\.text).joined(separator: " "),
      lines: usedLines,
      confidence: usedLines.isEmpty ? Double(text.transcript.isEmpty ? 0 : 1) : 0,
      boundingBox: normalizedBoundingBox(from: text.boundingRegion.boundingBox.cgRect),
      alignment: alignment(from: text.textAlignment)
    )
  }

  private static func assign(
    _ words: [RecognizedTextObservation],
    to lines: inout [VisionLineSnapshot]
  ) {
    guard !words.isEmpty else { return }
    var mutableLines = lines
    let wordRects = words.map {
      normalizedBoundingBox(from: $0.boundingRegion.boundingBox.cgRect)
    }

    for (wordIndex, word) in words.enumerated() where !word.transcript.isEmpty {
      let wordRect = wordRects[wordIndex]
      let lineIndex = mutableLines.indices.max {
        intersectionArea(mutableLines[$0], wordRect)
          < intersectionArea(mutableLines[$1], wordRect)
      }

      guard let lineIndex else { continue }
      let oldLine = mutableLines[lineIndex]
      mutableLines[lineIndex] = VisionLineSnapshot(
        text: oldLine.text,
        confidence: oldLine.confidence,
        boundingBox: oldLine.boundingBox,
        isTitle: oldLine.isTitle,
        words: oldLine.words + [
          VisionWordSnapshot(
            text: word.transcript,
            confidence: Double(word.confidence),
            boundingBox: wordRect
          )
        ]
      )
    }
  }

  private static func intersectionArea(_ line: VisionLineSnapshot, _ word: CGRect) -> CGFloat {
    let intersection = line.boundingBox.intersection(word)
    guard !intersection.isNull else { return 0 }
    return max(0, intersection.width) * max(0, intersection.height)
  }

  private static func alignment(
    from alignment: DocumentObservation.Container.Text.Alignment?
  ) -> CanonicalTextAlignment? {
    switch alignment {
    case .leading: .left
    case .center: .center
    case .trailing: .right
    case nil: nil
    @unknown default: nil
    }
  }

  private static func normalizedBoundingBox(from rect: CGRect) -> CGRect {
    let clampedX = min(max(rect.minX, 0), 1)
    let clampedY = min(max(rect.minY, 0), 1)
    let clampedWidth = min(max(rect.width, 0), 1 - clampedX)
    let clampedHeight = min(max(rect.height, 0), 1 - clampedY)
    return CGRect(
      x: clampedX,
      y: 1 - clampedY - clampedHeight,
      width: clampedWidth,
      height: clampedHeight
    )
  }
}

/// Converts target-independent Vision evidence into canonical blocks and spans.
/// No display sanitizer is used here so canonical evidence remains immutable.
enum VisionDocumentCanonicalMapper {
  static func canonicalDocument(from snapshot: VisionDocumentSnapshot) -> CanonicalDocument {
    var drafts: [BlockDraft] = []

    if let title = effectiveTitle(snapshot) {
      drafts.append(contentsOf: textBlocks(title, kind: .title, context: "title"))
    }

    for (index, paragraph) in snapshot.paragraphs.enumerated() {
      drafts.append(
        contentsOf: textBlocks(paragraph, kind: .paragraph, context: "paragraph-\(index)"))
    }

    for (tableIndex, table) in snapshot.tables.enumerated() {
      drafts.append(contentsOf: tableBlocks(table, tableIndex: tableIndex))
    }

    for (listIndex, list) in snapshot.lists.enumerated() {
      drafts.append(contentsOf: listBlocks(list, listIndex: listIndex))
    }

    if snapshot.paragraphs.isEmpty, snapshot.tables.isEmpty, snapshot.lists.isEmpty,
      let fallback = snapshot.fallbackText, !fallback.transcript.isEmpty
    {
      drafts.append(contentsOf: textBlocks(fallback, kind: .paragraph, context: "fallback"))
    }

    let orderedBlocks = Self.readingOrderedBlocks(from: drafts)
    let documentSeed = orderedBlocks.reduce(into: "canonical-document\nimage") { seed, block in
      seed += "\n\(block.kind.rawValue):\(block.text):\(block.confidence)"
    }

    return CanonicalDocument(
      id: deterministicID(seed: documentSeed),
      origin: .image,
      detectedLanguage: nil,
      blocks: orderedBlocks
    )
  }

  private static func effectiveTitle(_ snapshot: VisionDocumentSnapshot) -> VisionTextSnapshot? {
    if let title = snapshot.title, !title.transcript.isEmpty {
      return title
    }

    guard let firstLine = snapshot.paragraphs.first?.lines.first(where: \.isTitle) else {
      return nil
    }
    return VisionTextSnapshot(
      transcript: firstLine.text,
      lines: [firstLine],
      confidence: firstLine.confidence,
      boundingBox: firstLine.boundingBox,
      alignment: nil
    )
  }

  private static func textBlocks(
    _ text: VisionTextSnapshot,
    kind: CanonicalBlockKind,
    context: String
  ) -> [BlockDraft] {
    guard !text.transcript.isEmpty else { return [] }
    let spans = spans(for: text, context: context)
    let confidence = confidence(for: text)

    return [
      BlockDraft(
        block: CanonicalBlock(
          id: deterministicID(
            seed:
              "block\n\(context)\n\(kind.rawValue)\n\(text.transcript)\n\(boxSeed(text.boundingBox))"
          ),
          order: 0,
          kind: kind,
          text: text.transcript,
          spans: spans,
          geometry: geometry(from: text.boundingBox, alignment: text.alignment),
          confidence: confidence
        ),
        boundingBox: text.boundingBox.isNull ? nil : text.boundingBox
      )
    ]
  }

  private static func tableBlocks(
    _ table: VisionTableSnapshot,
    tableIndex: Int
  ) -> [BlockDraft] {
    var drafts: [BlockDraft] = []
    var tableText = ""
    var tableSpans: [CanonicalSpan] = []

    for (rowIndex, row) in table.rows.enumerated() {
      for (columnIndex, cell) in row.enumerated() {
        let cellText = cell.content.transcript
        if !cellText.isEmpty {
          tableSpans.append(
            contentsOf: spans(
              for: cell.content,
              context: "table-\(tableIndex)-r\(rowIndex)-c\(columnIndex)",
              overrideText: cellText,
              rangeOffset: tableText.utf16.count
            )
          )
          tableText += cellText
        }

        if columnIndex < row.count - 1 { tableText += "\t" }
      }
      if rowIndex < table.rows.count - 1 { tableText += "\n" }
    }

    if !tableText.isEmpty {
      let tableConfidence = table.rows.flatMap(\.self).map { confidence(for: $0.content) }
      drafts.append(
        BlockDraft(
          block: CanonicalBlock(
            id: deterministicID(
              seed: "block\ntable-\(tableIndex)\n\(tableText)\n\(boxSeed(table.boundingBox))"),
            order: 0,
            kind: .table,
            text: tableText,
            spans: tableSpans,
            geometry: geometry(from: table.boundingBox),
            confidence: average(tableConfidence)
          ),
          boundingBox: table.boundingBox.isNull ? nil : table.boundingBox
        )
      )
    }

    for (rowIndex, row) in table.rows.enumerated() {
      for (columnIndex, cell) in row.enumerated() where !cell.content.transcript.isEmpty {
        let cellConfidence = confidence(for: cell.content)
        drafts.append(
          BlockDraft(
            block: CanonicalBlock(
              id: deterministicID(
                seed:
                  "block\ntable-cell-\(tableIndex)-r\(rowIndex)-c\(columnIndex)\n\(cell.content.transcript)\n\(boxSeed(cell.boundingBox))"
              ),
              order: 0,
              kind: .tableCell,
              text: cell.content.transcript,
              spans: spans(
                for: cell.content,
                context: "table-cell-\(tableIndex)-r\(rowIndex)-c\(columnIndex)"
              ),
              geometry: geometry(from: cell.boundingBox),
              confidence: cellConfidence
            ),
            boundingBox: cell.boundingBox.isNull ? nil : cell.boundingBox
          )
        )
      }
    }

    return drafts
  }

  private static func listBlocks(
    _ list: VisionListSnapshot,
    listIndex: Int
  ) -> [BlockDraft] {
    var drafts: [BlockDraft] = []
    var listText = ""
    var listSpans: [CanonicalSpan] = []

    for (itemIndex, item) in list.items.enumerated() {
      let itemText =
        item.content.transcript.isEmpty
        ? ""
        : (item.marker.isEmpty
          ? item.content.transcript : "\(item.marker) \(item.content.transcript)")
      if !itemText.isEmpty {
        let range = listText.utf16.count..<(listText.utf16.count + itemText.utf16.count)
        listSpans.append(
          CanonicalSpan(
            id: deterministicID(
              seed:
                "span\nlist-\(listIndex)-item-\(itemIndex)\n\(itemText)\n\(boxSeed(item.boundingBox))"
            ),
            text: itemText,
            charRange: range,
            confidence: confidence(for: item.content),
            geometry: geometry(from: item.boundingBox)
          )
        )
        listText += itemText
      }

      guard !item.content.transcript.isEmpty else { continue }
      drafts.append(
        BlockDraft(
          block: CanonicalBlock(
            id: deterministicID(
              seed:
                "block\nlist-item-\(listIndex)-\(itemIndex)\n\(item.content.transcript)\n\(boxSeed(item.boundingBox))"
            ),
            order: 0,
            kind: .listItem,
            text: item.content.transcript,
            spans: spans(for: item.content, context: "list-item-\(listIndex)-\(itemIndex)"),
            geometry: geometry(from: item.boundingBox),
            confidence: confidence(for: item.content)
          ),
          boundingBox: item.boundingBox.isNull ? nil : item.boundingBox
        )
      )
    }

    if !listText.isEmpty {
      drafts.insert(
        BlockDraft(
          block: CanonicalBlock(
            id: deterministicID(
              seed: "block\nlist-\(listIndex)\n\(listText)\n\(boxSeed(list.boundingBox))"),
            order: 0,
            kind: .list,
            text: listText,
            spans: listSpans,
            geometry: geometry(from: list.boundingBox),
            confidence: average(list.items.map { confidence(for: $0.content) })
          ),
          boundingBox: list.boundingBox.isNull ? nil : list.boundingBox
        ),
        at: 0
      )
    }

    return drafts
  }

  private static func spans(
    for text: VisionTextSnapshot,
    context: String,
    overrideText: String? = nil,
    rangeOffset: Int = 0
  ) -> [CanonicalSpan] {
    let blockText = overrideText ?? text.transcript
    var spans: [CanonicalSpan] = []
    var searchStart = blockText.startIndex

    for (lineIndex, line) in text.lines.enumerated() where !line.text.isEmpty {
      guard let lineRange = blockText.range(of: line.text, range: searchStart..<blockText.endIndex)
      else {
        continue
      }
      let lower = rangeOffset + blockText.utf16Offset(of: lineRange.lowerBound)
      let upper = rangeOffset + blockText.utf16Offset(of: lineRange.upperBound)
      spans.append(
        CanonicalSpan(
          id: deterministicID(
            seed: "span\n\(context)-line-\(lineIndex)\n\(line.text)\n\(boxSeed(line.boundingBox))"),
          text: line.text,
          charRange: lower..<upper,
          confidence: line.confidence,
          geometry: geometry(from: line.boundingBox)
        )
      )

      var wordSearchStart = lineRange.lowerBound
      for (wordIndex, word) in line.words.enumerated() where !word.text.isEmpty {
        guard
          let wordRange = blockText.range(
            of: word.text,
            range: wordSearchStart..<lineRange.upperBound
          )
        else { continue }
        let wordLower = rangeOffset + blockText.utf16Offset(of: wordRange.lowerBound)
        let wordUpper = rangeOffset + blockText.utf16Offset(of: wordRange.upperBound)
        spans.append(
          CanonicalSpan(
            id: deterministicID(
              seed:
                "span\n\(context)-line-\(lineIndex)-word-\(wordIndex)\n\(word.text)\n\(boxSeed(word.boundingBox))"
            ),
            text: word.text,
            charRange: wordLower..<wordUpper,
            confidence: word.confidence,
            geometry: geometry(from: word.boundingBox)
          )
        )
        wordSearchStart = wordRange.upperBound
      }

      searchStart = lineRange.upperBound
    }

    if spans.isEmpty, !blockText.isEmpty {
      spans.append(
        CanonicalSpan(
          id: deterministicID(seed: "span\n\(context)\n\(blockText)"),
          text: blockText,
          charRange: rangeOffset..<(rangeOffset + blockText.utf16.count),
          confidence: text.confidence,
          geometry: geometry(from: text.boundingBox, alignment: text.alignment)
        )
      )
    }

    return spans
  }

  private static func readingOrderedBlocks(from drafts: [BlockDraft]) -> [CanonicalBlock] {
    let sorted = drafts.enumerated().sorted { left, right in
      let leftBox = left.element.boundingBox
      let rightBox = right.element.boundingBox

      if let leftBox, let rightBox {
        if abs(leftBox.minY - rightBox.minY) > 0.005 {
          return leftBox.minY < rightBox.minY
        }
        if abs(leftBox.minX - rightBox.minX) > 0.005 {
          return leftBox.minX < rightBox.minX
        }
      } else if leftBox != nil {
        return true
      } else if rightBox != nil {
        return false
      }
      return left.offset < right.offset
    }

    return sorted.enumerated().map { order, sortedDraft in
      var block = sortedDraft.element.block
      let hint = order
      let geometry = block.geometry.map {
        CanonicalGeometry(
          normalizedBoundingBox: $0.normalizedBoundingBox,
          readingOrderHint: hint,
          alignment: $0.alignment
        )
      }
      return CanonicalBlock(
        id: block.id,
        order: order,
        kind: block.kind,
        text: block.text,
        spans: block.spans,
        geometry: geometry,
        confidence: block.confidence
      )
    }
  }

  private static func confidence(for text: VisionTextSnapshot) -> Double {
    if text.lines.isEmpty {
      return clampConfidence(text.confidence)
    }
    return average(text.lines.map(\.confidence))
  }

  private static func geometry(
    from boundingBox: CGRect,
    alignment: CanonicalTextAlignment? = nil
  ) -> CanonicalGeometry? {
    guard !boundingBox.isNull, boundingBox.width > 0 || boundingBox.height > 0 else {
      return nil
    }
    return CanonicalGeometry(
      normalizedBoundingBox: boundingBox,
      readingOrderHint: nil,
      alignment: alignment
    )
  }

  private static func boxSeed(_ box: CGRect) -> String {
    "\(box.minX),\(box.minY),\(box.width),\(box.height)"
  }

  private static func average(_ values: [Double]) -> Double {
    guard !values.isEmpty else { return 0 }
    return clampConfidence(values.reduce(0, +) / Double(values.count))
  }

  private static func clampConfidence(_ value: Double) -> Double {
    min(max(value.isFinite ? value : 0, 0), 1)
  }

  static func deterministicID(seed: String) -> UUID {
    let digest = SHA256.hash(data: Data(seed.utf8))
    var bytes = Array(digest.prefix(16))
    bytes[6] = (bytes[6] & 0x0F) | 0x40
    bytes[8] = (bytes[8] & 0x3F) | 0x80
    return UUID(
      uuid: (
        bytes[0], bytes[1], bytes[2], bytes[3],
        bytes[4], bytes[5], bytes[6], bytes[7],
        bytes[8], bytes[9], bytes[10], bytes[11],
        bytes[12], bytes[13], bytes[14], bytes[15]
      )
    )
  }
}

private struct BlockDraft: Sendable {
  let block: CanonicalBlock
  let boundingBox: CGRect?
}

extension UIImage.Orientation {
  fileprivate var visionOrientation: CGImagePropertyOrientation {
    switch self {
    case .up: .up
    case .upMirrored: .upMirrored
    case .down: .down
    case .downMirrored: .downMirrored
    case .left: .left
    case .leftMirrored: .leftMirrored
    case .right: .right
    case .rightMirrored: .rightMirrored
    @unknown default: .up
    }
  }
}

extension StringProtocol {
  fileprivate func utf16Offset(of index: String.Index) -> Int {
    utf16.distance(from: startIndex, to: index)
  }
}

extension VisionDocumentSnapshot {
  fileprivate var isEmpty: Bool {
    let hasTitle = title?.transcript.isEmpty == false
    let hasFallback = fallbackText?.transcript.isEmpty == false
    let hasParagraphs = paragraphs.contains { !$0.transcript.isEmpty }
    let hasLists = lists.contains { !$0.items.isEmpty }
    let hasTables = tables.contains { !$0.rows.isEmpty }
    return !(hasTitle || hasFallback || hasParagraphs || hasLists || hasTables)
  }
}
