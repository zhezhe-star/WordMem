import Foundation
import Translation
import XCTest

@testable import WordMem

final class DocumentTranslationEngineTests: XCTestCase {
  func testInstalledAvailabilityTranslatesCanonicalBlocksAndRetainsIdentifiers() async throws {
    let document = makeDocument(
      [
        makeBlock(id: makeUUID(1), text: "The garden grows quickly."),
        makeBlock(id: makeUUID(2), text: "Please review the map."),
      ]
    )
    let availability = FakeAvailability(status: .installed)
    let engine = DocumentTranslationEngine(
      availabilityChecker: availability,
      languageDetector: FakeDetector(language: Locale.Language(identifier: "en"))
    )
    let session = FakeTranslationSession(
      responsesByID: [
        makeUUID(1): "花园生长得很快。",
        makeUUID(2): "请查看地图。",
      ]
    )

    let phase = await engine.availabilityPhase(
      for: document,
      target: Locale.Language(identifier: "zh-Hans")
    )
    let translated = try await engine.translate(
      document: document,
      target: Locale.Language(identifier: "zh-Hans"),
      using: session
    )

    XCTAssertEqual(phase, .translating)
    XCTAssertEqual(availability.requestedPairs.count, 1)
    XCTAssertEqual(
      availability.requestedPairs.first?.source,
      Locale.Language(identifier: "en")
    )
    XCTAssertEqual(
      availability.requestedPairs.first?.target,
      Locale.Language(identifier: "zh-Hans")
    )
    XCTAssertEqual(translated.sourceDocumentID, document.id)
    XCTAssertEqual(translated.blocks.map(\.sourceBlockID), document.blocks.map(\.id))
    XCTAssertEqual(translated.blocks.map(\.state), [.systemTranslated, .systemTranslated])
    XCTAssertEqual(
      translated.blocks.map(\.spans.first?.sourceSpanID),
      document.blocks.map(\.spans.first?.id)
    )
    XCTAssertEqual(translated.blocks.map(\.text), ["花园生长得很快。", "请查看地图。"])
  }

  func testSupportedNotInstalledAvailabilityEntersDownloadPhaseWithoutSession() async {
    let document = makeDocument([makeBlock(id: makeUUID(1), text: "Hello")])
    let availability = FakeAvailability(status: .supportedNotInstalled)
    let engine = DocumentTranslationEngine(
      availabilityChecker: availability,
      languageDetector: FakeDetector(language: Locale.Language(identifier: "en"))
    )
    let session = FakeTranslationSession()

    let phase = await engine.availabilityPhase(
      for: document,
      target: Locale.Language(identifier: "zh-Hans")
    )

    XCTAssertEqual(phase, .needsLanguageDownload)
    XCTAssertTrue(session.translateCalls.isEmpty)
  }

  func testUnsupportedPairEntersUnsupportedPhaseWithoutSession() async {
    let document = makeDocument([makeBlock(id: makeUUID(1), text: "Hello")])
    let availability = FakeAvailability(status: .unsupported)
    let engine = DocumentTranslationEngine(
      availabilityChecker: availability,
      languageDetector: FakeDetector(language: Locale.Language(identifier: "en"))
    )
    let session = FakeTranslationSession()

    let phase = await engine.availabilityPhase(
      for: document,
      target: Locale.Language(identifier: "zh-Hans")
    )

    XCTAssertEqual(phase, .unsupportedLanguagePair)
    XCTAssertTrue(session.translateCalls.isEmpty)
  }

  func testMissingDetectedLanguageFailsExplicitlyWithoutSession() async {
    let document = makeDocument([makeBlock(id: makeUUID(1), text: "Hello")])
    let engine = DocumentTranslationEngine(
      availabilityChecker: FakeAvailability(status: .installed),
      languageDetector: FakeDetector(language: nil)
    )
    let session = FakeTranslationSession()

    let phase = await engine.availabilityPhase(
      for: document,
      target: Locale.Language(identifier: "zh-Hans")
    )

    XCTAssertEqual(phase, .failed(.languageDetection))
    XCTAssertTrue(session.translateCalls.isEmpty)
  }

  func testInternalSessionFailureMapsToFailedPhase() async throws {
    let document = makeDocument([makeBlock(id: makeUUID(1), text: "Hello")])
    let engine = DocumentTranslationEngine(
      availabilityChecker: FakeAvailability(status: .installed),
      languageDetector: FakeDetector(language: Locale.Language(identifier: "en"))
    )
    let session = ThrowingTranslationSession(throwable: GenericTranslationFailure())

    do {
      _ = try await engine.translate(
        document: document,
        target: Locale.Language(identifier: "zh-Hans"),
        using: session
      )
      XCTFail("Expected internal translation failure.")
    } catch {
      XCTAssertEqual(
        DocumentTranslationStateMapper.phase(for: error),
        .failed(.internalFailure("generic translation failure"))
      )
    }
  }

  func testMissingBatchResponseFailsInsteadOfBeingDropped() async throws {
    let document = makeDocument(
      [
        makeBlock(id: makeUUID(1), text: "First"),
        makeBlock(id: makeUUID(2), text: "Second"),
      ]
    )
    let engine = DocumentTranslationEngine(
      availabilityChecker: FakeAvailability(status: .installed),
      languageDetector: FakeDetector(language: Locale.Language(identifier: "en"))
    )
    let session = FakeTranslationSession(
      responsesByID: [makeUUID(1): "第一"]
    )

    do {
      _ = try await engine.translate(
        document: document,
        target: Locale.Language(identifier: "zh-Hans"),
        using: session
      )
      XCTFail("Expected missing response failure.")
    } catch let error as DocumentTranslationServiceError {
      XCTAssertEqual(
        error,
        .missingResponse(clientIdentifier: makeUUID(2).uuidString)
      )
    }
  }

  @MainActor
  func testRetrySucceedsAfterInternalFailureAndInvalidateResetsLifecycle() async {
    let document = makeDocument([makeBlock(id: makeUUID(1), text: "Hello")])
    let engine = DocumentTranslationEngine(
      availabilityChecker: FakeAvailability(status: .installed),
      languageDetector: FakeDetector(language: Locale.Language(identifier: "en"))
    )
    let session = FailingThenSucceedingSession(
      firstError: GenericTranslationFailure(),
      success: "你好"
    )
    let importSession = ImportDocumentSession(
      document: document,
      targetLanguage: Locale.Language(identifier: "zh-Hans"),
      engine: engine
    )

    importSession.beginTranslation()
    await importSession.handle(session)

    XCTAssertEqual(importSession.phase, .translating)
    XCTAssertTrue(importSession.usesLowLatencyTranslation)
    XCTAssertEqual(importSession.configuration?.preferredStrategy, .lowLatency)

    await importSession.handle(session)
    XCTAssertEqual(importSession.phase, .completed)
    XCTAssertEqual(importSession.translatedDocument?.blocks.first?.text, "你好")
    XCTAssertEqual(importSession.translatedDocument?.blocks.first?.sourceBlockID, makeUUID(1))
    XCTAssertNil(importSession.configuration)

    importSession.invalidate()
    XCTAssertEqual(importSession.phase, .idle)
    XCTAssertFalse(importSession.usesLowLatencyTranslation)
    XCTAssertNil(importSession.configuration)
  }

  @MainActor
  func testRepeatedTranslationFailureStopsAfterLegacyFallback() async {
    let document = makeDocument([makeBlock(id: makeUUID(1), text: "Hello")])
    let engine = DocumentTranslationEngine(
      availabilityChecker: FakeAvailability(status: .installed),
      languageDetector: FakeDetector(language: Locale.Language(identifier: "en"))
    )
    let importSession = ImportDocumentSession(
      document: document,
      targetLanguage: Locale.Language(identifier: "zh-Hans"),
      engine: engine
    )
    let session = ThrowingTranslationSession(throwable: GenericTranslationFailure())

    importSession.beginTranslation()
    await importSession.handle(session)
    XCTAssertEqual(importSession.phase, .translating)
    XCTAssertTrue(importSession.usesLowLatencyTranslation)

    await importSession.handle(session)
    XCTAssertEqual(importSession.phase, .failed(.internalFailure("generic translation failure")))
    XCTAssertNil(importSession.configuration)
  }

  @MainActor
  func testUserEditedTranslationHasPrecedenceOnRetry() async {
    let first = makeBlock(id: makeUUID(1), text: "First")
    let second = makeBlock(id: makeUUID(2), text: "Second")
    let document = makeDocument([first, second])
    let engine = DocumentTranslationEngine(
      availabilityChecker: FakeAvailability(status: .installed),
      languageDetector: FakeDetector(language: Locale.Language(identifier: "en"))
    )
    let session = FakeTranslationSession(
      responsesByID: [
        makeUUID(1): "系统第一",
        makeUUID(2): "系统第二",
      ]
    )
    let importSession = ImportDocumentSession(
      document: document,
      targetLanguage: Locale.Language(identifier: "zh-Hans"),
      engine: engine
    )

    importSession.userEditedTranslation(blockID: first.id, text: "用户编辑第一")
    importSession.beginTranslation()
    await importSession.handle(session)

    XCTAssertEqual(session.translateCalls.count, 1)
    XCTAssertEqual(session.translateCalls.first?.count, 1)
    XCTAssertEqual(session.translateCalls.first?.first?.sourceBlockID, second.id)
    XCTAssertEqual(
      importSession.translatedDocument?.blocks.first { $0.sourceBlockID == first.id }?.text,
      "用户编辑第一")
    XCTAssertEqual(
      importSession.translatedDocument?.blocks.first { $0.sourceBlockID == first.id }?.state,
      .userEdited)
    XCTAssertEqual(
      importSession.translatedDocument?.blocks.first { $0.sourceBlockID == second.id }?.state,
      .systemTranslated)
  }

  @MainActor
  func testNoCandidateDocumentCompletesWithNoTranslatedBlocks() async {
    let document = makeDocument([])
    let engine = DocumentTranslationEngine(
      availabilityChecker: FakeAvailability(status: .installed),
      languageDetector: FakeDetector(language: Locale.Language(identifier: "en"))
    )
    let session = FakeTranslationSession()
    let importSession = ImportDocumentSession(
      document: document,
      targetLanguage: Locale.Language(identifier: "zh-Hans"),
      engine: engine
    )

    importSession.beginTranslation()
    await importSession.handle(session)

    XCTAssertEqual(importSession.phase, .completed)
    XCTAssertTrue(importSession.translatedDocument?.blocks.isEmpty ?? false)
    XCTAssertTrue(session.translateCalls.isEmpty)
  }

  func testHighFidelityConfigurationIsInvalidatedForRetry() {
    let source = Locale.Language(identifier: "en")
    let target = Locale.Language(identifier: "zh-Hans")
    let initial = DocumentTranslationSessionFactory.highFidelity(source: source, target: target)

    XCTAssertEqual(initial.preferredStrategy, .highFidelity)
    let refreshed = DocumentTranslationSessionFactory.refreshedHighFidelity(
      initial,
      source: source,
      target: target
    )
    XCTAssertEqual(refreshed.preferredStrategy, .highFidelity)
    XCTAssertGreaterThan(refreshed.version, initial.version)
  }

  func testLowLatencyFallbackConfigurationIsInvalidatedForRetry() {
    let source = Locale.Language(identifier: "en")
    let target = Locale.Language(identifier: "zh-Hans")
    let initial = DocumentTranslationSessionFactory.highFidelity(source: source, target: target)

    let refreshed = DocumentTranslationSessionFactory.refreshedLowLatency(
      initial,
      source: source,
      target: target
    )

    XCTAssertEqual(refreshed.preferredStrategy, .lowLatency)
    XCTAssertGreaterThan(refreshed.version, initial.version)
  }

  @MainActor
  func testInitialTranslationConfigurationIsReadyForFirstTask() {
    let baseline = DocumentTranslationSessionFactory.highFidelity(
      source: Locale.Language(identifier: "en"),
      target: Locale.Language(identifier: "zh-Hans")
    )
    let session = ImportDocumentSession(document: makeDocument([]))

    session.beginTranslation()

    XCTAssertEqual(session.configuration?.preferredStrategy, .highFidelity)
    XCTAssertEqual(session.configuration?.version, baseline.version)
  }

  @MainActor
  func testAvailabilityCheckDoesNotStartFirstTranslationTask() async throws {
    let document = makeDocument([makeBlock(id: makeUUID(1), text: "Hello")])
    let session = ImportDocumentSession(
      document: document,
      engine: DocumentTranslationEngine(
        availabilityChecker: FakeAvailability(status: .installed),
        languageDetector: FakeDetector(language: Locale.Language(identifier: "en"))
      )
    )

    await session.checkAvailability()

    XCTAssertEqual(session.phase, .translating)
    XCTAssertNil(session.configuration)

    session.beginTranslation()
    XCTAssertNotNil(session.configuration)
  }

  @MainActor
  func testCancelledTranslationTaskSchedulesARetryableConfiguration() async throws {
    let document = makeDocument([makeBlock(id: makeUUID(1), text: "Hello")])
    let engine = DocumentTranslationEngine(
      availabilityChecker: FakeAvailability(status: .installed),
      languageDetector: FakeDetector(language: Locale.Language(identifier: "en"))
    )
    let importSession = ImportDocumentSession(
      document: document,
      engine: engine
    )
    importSession.beginTranslation()
    let initialConfiguration = try XCTUnwrap(importSession.configuration)

    await importSession.handle(CancellingTranslationSession())

    XCTAssertEqual(importSession.phase, .translating)
    let retriedConfiguration = try XCTUnwrap(importSession.configuration)
    XCTAssertGreaterThan(retriedConfiguration.version, initialConfiguration.version)
  }

  private func makeDocument(_ blocks: [CanonicalBlock]) -> CanonicalDocument {
    CanonicalDocument(
      id: makeUUID(0),
      origin: .pastedText,
      detectedLanguage: nil,
      blocks: blocks
    )
  }

  private func makeBlock(id: UUID, text: String) -> CanonicalBlock {
    CanonicalBlock(
      id: id,
      order: Int(id.uuidString.prefix(2), radix: 16) ?? 0,
      kind: .paragraph,
      text: text,
      spans: [
        CanonicalSpan(
          id: UUID(),
          text: text,
          charRange: 0..<text.utf16.count,
          confidence: 1,
          geometry: nil
        )
      ],
      geometry: nil,
      confidence: 1
    )
  }

  private func makeUUID(_ value: UInt8) -> UUID {
    UUID(
      uuid: (
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, value
      ))
  }
}

private struct FakeDetector: DocumentLanguageDetecting {
  let language: Locale.Language?

  func detectLanguage(in text: String) -> Locale.Language? {
    language
  }
}

private final class FakeAvailability: DocumentLanguageAvailabilityChecking, @unchecked Sendable {
  let status: DocumentLanguageAvailabilityStatus
  private(set) var requestedPairs: [(source: Locale.Language, target: Locale.Language)] = []

  init(status: DocumentLanguageAvailabilityStatus) {
    self.status = status
  }

  func status(
    from source: Locale.Language,
    to target: Locale.Language
  ) async throws -> DocumentLanguageAvailabilityStatus {
    requestedPairs.append((source, target))
    return status
  }
}

private final class FakeTranslationSession: DocumentTranslationSessionHandling, @unchecked Sendable
{
  let responsesByID: [UUID: String]
  private(set) var translateCalls: [[DocumentTranslationRequest]] = []

  init(responsesByID: [UUID: String] = [:]) {
    self.responsesByID = responsesByID
  }

  func translate(
    _ requests: [DocumentTranslationRequest]
  ) async throws -> [DocumentTranslationResponse] {
    translateCalls.append(requests)
    return requests.compactMap { request in
      responsesByID[request.sourceBlockID].map {
        DocumentTranslationResponse(
          clientIdentifier: request.clientIdentifier,
          targetText: $0
        )
      }
    }
  }
}

private struct ThrowingTranslationSession: DocumentTranslationSessionHandling {
  let throwable: Error

  func translate(
    _ requests: [DocumentTranslationRequest]
  ) async throws -> [DocumentTranslationResponse] {
    throw throwable
  }
}

private final class FailingThenSucceedingSession: DocumentTranslationSessionHandling,
  @unchecked Sendable
{
  private let firstError: Error
  private let success: String
  private var hasFailed = false

  init(firstError: Error, success: String) {
    self.firstError = firstError
    self.success = success
  }

  func translate(
    _ requests: [DocumentTranslationRequest]
  ) async throws -> [DocumentTranslationResponse] {
    if !hasFailed {
      hasFailed = true
      throw firstError
    }
    return requests.map {
      DocumentTranslationResponse(clientIdentifier: $0.clientIdentifier, targetText: success)
    }
  }
}

private struct GenericTranslationFailure: Error, CustomStringConvertible {
  var description: String { "generic translation failure" }
}

private struct CancellingTranslationSession: DocumentTranslationSessionHandling {
  func translate(
    _ requests: [DocumentTranslationRequest]
  ) async throws -> [DocumentTranslationResponse] {
    throw CancellationError()
  }
}
