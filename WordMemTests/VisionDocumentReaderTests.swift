import CoreGraphics
import Foundation
import UIKit
import XCTest

@testable import WordMem

final class VisionDocumentReaderTests: XCTestCase {
  func testTitleParagraphListAndTableMappingUsesStableCanonicalEvidence() throws {
    let snapshot = Self.makeSnapshot()
    let document = VisionDocumentCanonicalMapper.canonicalDocument(from: snapshot)

    XCTAssertEqual(document.origin, .image)
    XCTAssertEqual(
      document.blocks.map(\.kind),
      [
        .title, .paragraph, .list, .listItem, .listItem, .table, .tableCell,
        .tableCell, .tableCell, .tableCell,
      ])
    XCTAssertEqual(
      document.blocks.map(\.text),
      [
        "Quarterly Report",
        "Revenue increased after the redesign.",
        "• Ship the reader• Test the mapper",
        "Ship the reader",
        "Test the mapper",
        "Metric\tChange\nRevenue\t18%",
        "Metric",
        "Change",
        "Revenue",
        "18%",
      ])

    let title = try XCTUnwrap(document.blocks.first)
    XCTAssertEqual(title.order, 0)
    XCTAssertEqual(title.confidence, 0.97, accuracy: 0.001)
    XCTAssertEqual(title.geometry?.readingOrderHint, 0)
    XCTAssertEqual(
      title.geometry?.normalizedBoundingBox, CGRect(x: 0.1, y: 0.08, width: 0.5, height: 0.05))

    let paragraph = try XCTUnwrap(document.blocks.first { $0.kind == .paragraph })
    XCTAssertEqual(paragraph.text, "Revenue increased after the redesign.")
    XCTAssertEqual(
      paragraph.spans.map(\.text),
      [
        "Revenue increased after the redesign.",
        "Revenue",
        "increased",
      ])
    XCTAssertEqual(paragraph.spans[1].charRange, 0..<7)
    XCTAssertEqual(paragraph.spans[1].confidence, 0.96, accuracy: 0.001)
    XCTAssertEqual(paragraph.spans[2].charRange, 8..<17)
    XCTAssertEqual(
      paragraph.geometry?.normalizedBoundingBox, CGRect(x: 0.1, y: 0.2, width: 0.65, height: 0.04))

    let listContainer = try XCTUnwrap(document.blocks.first { $0.kind == .list })
    XCTAssertEqual(listContainer.text, "• Ship the reader• Test the mapper")
    XCTAssertEqual(listContainer.spans.map(\.text), ["• Ship the reader", "• Test the mapper"])

    let table = try XCTUnwrap(document.blocks.first { $0.kind == .table })
    XCTAssertEqual(table.spans.map(\.text), ["Metric", "Change", "Revenue", "18%"])
    XCTAssertEqual(table.spans[2].charRange, 14..<21)
    XCTAssertTrue(table.spans.allSatisfy { $0.geometry?.normalizedBoundingBox != nil })
  }

  func testMappingIsDeterministicAcrossRepeatedObservations() {
    let first = VisionDocumentCanonicalMapper.canonicalDocument(from: Self.makeSnapshot())
    let second = VisionDocumentCanonicalMapper.canonicalDocument(from: Self.makeSnapshot())

    XCTAssertEqual(first, second)
    let identifiers = first.blocks.flatMap { [$0.id] + $0.spans.map(\.id) }
    XCTAssertEqual(identifiers.count, Set(identifiers).count)
  }

  func testReadingOrderUsesGeometryWhilePreservingEvidence() {
    let upper = VisionTextSnapshot(
      transcript: "Upper",
      lines: [
        Self.makeLine(
          "Upper", confidence: 0.9, rect: CGRect(x: 0.1, y: 0.1, width: 0.2, height: 0.02))
      ],
      boundingBox: CGRect(x: 0.1, y: 0.1, width: 0.2, height: 0.02)
    )
    let lower = VisionTextSnapshot(
      transcript: "Lower",
      lines: [
        Self.makeLine(
          "Lower", confidence: 0.9, rect: CGRect(x: 0.5, y: 0.5, width: 0.2, height: 0.02))
      ],
      boundingBox: CGRect(x: 0.5, y: 0.5, width: 0.2, height: 0.02)
    )
    let snapshot = VisionDocumentSnapshot(paragraphs: [lower, upper])

    let document = VisionDocumentCanonicalMapper.canonicalDocument(from: snapshot)

    XCTAssertEqual(document.blocks.map(\.text), ["Upper", "Lower"])
    XCTAssertEqual(document.blocks.map(\.order), [0, 1])
    XCTAssertEqual(document.blocks.map(\.geometry?.readingOrderHint), [0, 1])
  }

  func testConfidenceIsPreservedWithoutArtificialInflation() throws {
    let document = VisionDocumentCanonicalMapper.canonicalDocument(from: Self.makeSnapshot())
    let paragraph = try XCTUnwrap(document.blocks.first { $0.kind == .paragraph })
    let word = try XCTUnwrap(paragraph.spans.first { $0.text == "increased" })

    XCTAssertEqual(word.confidence, 0.72, accuracy: 0.001)
    XCTAssertEqual(paragraph.confidence, 0.95, accuracy: 0.001)
  }

  func testSanitizerFiltersDisplayAndCandidateTextWithoutMutatingCanonicalEvidence() throws {
    let document = VisionDocumentCanonicalMapper.canonicalDocument(from: Self.makeSnapshot())
    let rawTable = try XCTUnwrap(document.blocks.first { $0.kind == .table })
    let rawParagraph = try XCTUnwrap(document.blocks.first { $0.kind == .paragraph })
    let rawText = [
      "12:30",
      "5G",
      rawParagraph.text,
      rawTable.text,
    ].joined(separator: "\n")

    let filteredLines = OCRTextSanitizer.sanitizedLines(from: rawText)

    XCTAssertFalse(filteredLines.contains("12:30"))
    XCTAssertFalse(filteredLines.contains("5G"))
    XCTAssertTrue(filteredLines.contains(rawParagraph.text))
    XCTAssertTrue(filteredLines.contains("Metric\tChange"))
    XCTAssertTrue(filteredLines.contains("Revenue\t18%"))
    XCTAssertEqual(
      try XCTUnwrap(document.blocks.first { $0.kind == .table }).text,
      rawTable.text
    )
    XCTAssertEqual(
      try XCTUnwrap(document.blocks.first { $0.kind == .paragraph }).text,
      rawParagraph.text
    )
  }

  func testFakeProviderFeedsMapperThroughImageDocumentService() async throws {
    let provider = FakeVisionDocumentObservationProvider(snapshot: Self.makeSnapshot())
    let reader = VisionDocumentReader(observationProvider: provider)
    let imageData = try XCTUnwrap(makeJPEGData())

    let document = try await reader.recognizeDocument(in: imageData)

    XCTAssertEqual(document.blocks.map(\.kind).contains(.title), true)
    XCTAssertEqual(provider.requestedOrientations, [.up])
  }

  @MainActor
  func testTranslationMetadataUsesChildUnitsWithoutDuplicatingContainers() async throws {
    let document = VisionDocumentCanonicalMapper.canonicalDocument(from: Self.makeSnapshot())
    let model = DocumentImportReviewModel(
      advisor: ImportWordAdvisor(
        lemmaProvider: NoopVisionLemmaProvider(),
        spellingSuggester: NoopVisionSpellingSuggester(),
        availability: UnavailableVisionDictionary()
      )
    )
    model.documentSessionFactory = { canonicalDocument in
      ImportDocumentSession(
        document: canonicalDocument,
        engine: DocumentTranslationEngine(
          availabilityChecker: InstalledVisionAvailabilityChecker(),
          languageDetector: EnglishVisionLanguageDetector()
        )
      )
    }
    let fullDisplayText = document.blocks.map(\.text).joined(separator: "\n")

    await model.prepareImageDocument(document, displayText: fullDisplayText)
    guard let session = model.documentSession else {
      return XCTFail("Document session should exist after preparation.")
    }
    await session.handle(SourceEchoTranslationSession())

    XCTAssertEqual(session.phase, .completed)
    XCTAssertEqual(model.preparedDisplayText, fullDisplayText)
    XCTAssertEqual(session.document.blocks.map(\.kind).count, 10)
    XCTAssertEqual(session.document, document)
    XCTAssertTrue(document.blocks.contains { $0.kind == .list })
    XCTAssertTrue(document.blocks.contains { $0.kind == .table })

    let translated = try XCTUnwrap(session.translatedDocument)
    let sourceByTranslatedID = Dictionary(
      uniqueKeysWithValues: document.blocks.map { ($0.id, $0) }
    )
    let translatedSources = translated.blocks.compactMap { block in
      sourceByTranslatedID[block.sourceBlockID]
    }
    let expectedSourceKinds: [CanonicalBlockKind] = [
      .title, .paragraph, .listItem, .listItem, .tableCell, .tableCell, .tableCell,
      .tableCell,
    ]
    XCTAssertEqual(
      translatedSources.map(\.kind),
      expectedSourceKinds
    )
    XCTAssertEqual(
      model.translatedText, translatedSources.map { "\($0.text)译" }.joined(separator: "\n"))
    for container in document.blocks where container.kind == .list || container.kind == .table {
      XCTAssertFalse(model.translatedText?.contains(container.text) ?? true)
    }
    XCTAssertTrue(model.chips.map(\.text).contains("Revenue"))
  }

  private static func makeSnapshot() -> VisionDocumentSnapshot {
    let titleLine = makeLine(
      "Quarterly Report",
      confidence: 0.97,
      rect: CGRect(x: 0.1, y: 0.08, width: 0.5, height: 0.05)
    )
    let title = VisionTextSnapshot(
      transcript: titleLine.text,
      lines: [titleLine],
      confidence: 0.97,
      boundingBox: titleLine.boundingBox
    )

    let paragraphLine = makeLine(
      "Revenue increased after the redesign.",
      confidence: 0.95,
      rect: CGRect(x: 0.1, y: 0.2, width: 0.65, height: 0.04),
      words: [
        VisionWordSnapshot("Revenue", 0.96, CGRect(x: 0.1, y: 0.2, width: 0.08, height: 0.03)),
        VisionWordSnapshot("increased", 0.72, CGRect(x: 0.19, y: 0.2, width: 0.1, height: 0.03)),
      ]
    )
    let paragraph = VisionTextSnapshot(
      transcript: paragraphLine.text,
      lines: [paragraphLine],
      boundingBox: paragraphLine.boundingBox
    )

    let firstItemLine = makeLine(
      "Ship the reader",
      confidence: 0.94,
      rect: CGRect(x: 0.1, y: 0.3, width: 0.25, height: 0.025)
    )
    let secondItemLine = makeLine(
      "Test the mapper",
      confidence: 0.91,
      rect: CGRect(x: 0.1, y: 0.34, width: 0.25, height: 0.025)
    )
    let list = VisionListSnapshot(
      items: [
        VisionListItemSnapshot(
          marker: "•",
          content: VisionTextSnapshot(
            transcript: firstItemLine.text,
            lines: [firstItemLine],
            boundingBox: firstItemLine.boundingBox
          ),
          boundingBox: firstItemLine.boundingBox
        ),
        VisionListItemSnapshot(
          marker: "•",
          content: VisionTextSnapshot(
            transcript: secondItemLine.text,
            lines: [secondItemLine],
            boundingBox: secondItemLine.boundingBox
          ),
          boundingBox: secondItemLine.boundingBox
        ),
      ],
      boundingBox: CGRect(x: 0.1, y: 0.3, width: 0.3, height: 0.07)
    )

    let metricCell = makeCell("Metric", x: 0.1, y: 0.45)
    let changeCell = makeCell("Change", x: 0.22, y: 0.45)
    let revenueCell = makeCell("Revenue", x: 0.1, y: 0.5)
    let percentageCell = makeCell("18%", x: 0.22, y: 0.5)
    let table = VisionTableSnapshot(
      rows: [[metricCell, changeCell], [revenueCell, percentageCell]],
      boundingBox: CGRect(x: 0.1, y: 0.45, width: 0.28, height: 0.085)
    )

    return VisionDocumentSnapshot(
      title: title,
      paragraphs: [paragraph],
      tables: [table],
      lists: [list]
    )
  }

  private static func makeLine(
    _ text: String,
    confidence: Double,
    rect: CGRect,
    words: [VisionWordSnapshot] = []
  ) -> VisionLineSnapshot {
    VisionLineSnapshot(
      text: text,
      confidence: confidence,
      boundingBox: rect,
      words: words
    )
  }

  private static func makeCell(_ text: String, x: CGFloat, y: CGFloat) -> VisionTableCellSnapshot {
    let line = makeLine(
      text,
      confidence: 0.9,
      rect: CGRect(x: x, y: y, width: 0.1, height: 0.025)
    )
    return VisionTableCellSnapshot(
      content: VisionTextSnapshot(
        transcript: text,
        lines: [line],
        boundingBox: line.boundingBox
      ),
      boundingBox: line.boundingBox
    )
  }

  private func makeJPEGData() throws -> Data {
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    let image = UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8), format: format).image {
      context in
      UIColor.white.setFill()
      context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
    }
    return try XCTUnwrap(image.jpegData(compressionQuality: 0.9))
  }
}

extension VisionWordSnapshot {
  fileprivate init(_ text: String, _ confidence: Double, _ boundingBox: CGRect) {
    self.init(text: text, confidence: confidence, boundingBox: boundingBox)
  }
}

extension VisionLineSnapshot {
  fileprivate init(
    text: String,
    confidence: Double,
    boundingBox: CGRect,
    words: [VisionWordSnapshot]
  ) {
    self.init(
      text: text,
      confidence: confidence,
      boundingBox: boundingBox,
      isTitle: false,
      words: words
    )
  }
}

private final class FakeVisionDocumentObservationProvider: VisionDocumentObservationProviding,
  @unchecked Sendable
{
  private let snapshot: VisionDocumentSnapshot
  private(set) var requestedOrientations: [CGImagePropertyOrientation] = []

  init(snapshot: VisionDocumentSnapshot) {
    self.snapshot = snapshot
  }

  func snapshots(
    from cgImage: CGImage,
    orientation: CGImagePropertyOrientation
  ) async throws -> [VisionDocumentSnapshot] {
    requestedOrientations.append(orientation)
    return [snapshot]
  }
}

private struct SourceEchoTranslationSession: DocumentTranslationSessionHandling {
  func translate(
    _ requests: [DocumentTranslationRequest]
  ) async throws -> [DocumentTranslationResponse] {
    requests.map {
      DocumentTranslationResponse(
        clientIdentifier: $0.clientIdentifier,
        targetText: "\($0.sourceText)译"
      )
    }
  }
}

private struct InstalledVisionAvailabilityChecker: DocumentLanguageAvailabilityChecking {
  func status(
    from source: Locale.Language,
    to target: Locale.Language
  ) async throws -> DocumentLanguageAvailabilityStatus {
    .installed
  }
}

private struct EnglishVisionLanguageDetector: DocumentLanguageDetecting {
  func detectLanguage(in text: String) -> Locale.Language? {
    Locale.Language(identifier: "en")
  }
}

private struct UnavailableVisionDictionary: SystemDictionaryAuthorizing {
  func hasDefinition(forTerm term: String) async -> Bool {
    false
  }
}

private struct NoopVisionLemmaProvider: ImportWordLemmaProviding {
  func lemma(for word: String, context: String?) async -> String? {
    nil
  }
}

private struct NoopVisionSpellingSuggester: ImportWordSpellingSuggesting {
  func correction(for word: String) async -> String? {
    nil
  }
}
