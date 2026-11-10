import Foundation
import XCTest

@testable import WordMem

final class FoundationModelsCuratorTests: XCTestCase {
  // MARK: - Meaningful curation

  func testRecommendsMeaningfulWordsAndRejectsFunctionWords() {
    let assessments = Self.makeEntries([
      Self.entry(id: "study", isRecommended: true, score: 9),
      Self.entry(id: "case", isRecommended: true, score: 8),
      Self.entry(id: "chapter", isRecommended: true, score: 8),
      Self.entry(id: "am", isRecommended: false, score: 2, isFunctionWord: true),
      Self.entry(id: "is", isRecommended: false, score: 2, isFunctionWord: true),
      Self.entry(id: "are", isRecommended: false, score: 2, isFunctionWord: true),
    ])

    let result = FoundationModelsCandidateCurator.validated(
      assessments,
      knownIDs: ["study", "case", "chapter", "am", "is", "are"]
    )

    guard case .curated(let curated) = result else {
      return XCTFail("Expected curated result.")
    }
    let recommended = Set(curated.filter(\.isRecommended).map(\.candidateID))
    XCTAssertEqual(recommended, ["study", "case", "chapter"])
    let rejected = Set(curated.filter { !$0.isRecommended }.map(\.candidateID))
    XCTAssertEqual(rejected, ["am", "is", "are"])
  }

  func testFunctionWordClassificationOverridesAHighestScoreRecommendation() {
    let assessments = Self.makeEntries([
      Self.entry(
        id: "library", isRecommended: true, score: 9, isFunctionWord: false
      ),
      Self.entry(
        id: "is", isRecommended: true, score: 10, isFunctionWord: true
      ),
    ])

    let result = FoundationModelsCandidateCurator.validated(
      assessments,
      knownIDs: ["library", "is"]
    )

    guard case .curated(let curated) = result else {
      return XCTFail("Expected curated result.")
    }
    let recommended = Set(curated.filter(\.isRecommended).map(\.candidateID))
    XCTAssertEqual(recommended, ["library"])
  }

  func testRecommendedCandidateMustReachTheHighValueThreshold() {
    let assessments = Self.makeEntries([
      Self.entry(id: "library", isRecommended: true, score: 8),
      Self.entry(id: "case", isRecommended: true, score: 7),
    ])

    let result = FoundationModelsCandidateCurator.validated(
      assessments,
      knownIDs: ["library", "case"]
    )

    guard case .curated(let curated) = result else {
      return XCTFail("Expected curated result.")
    }
    let recommended = Set(curated.filter(\.isRecommended).map(\.candidateID))
    XCTAssertEqual(recommended, ["library"])
  }

  func testRejectsUnknownIDsAndNewWords() {
    let assessments = [
      Self.entry(id: "study", isRecommended: true, score: 8),
      Self.entry(id: "totally-new-word", isRecommended: true, score: 9),
      Self.entry(id: "  case  ", isRecommended: true, score: 7),
    ]

    let result = FoundationModelsCandidateCurator.validated(
      assessments,
      knownIDs: ["study", "case"]
    )

    guard case .curated(let curated) = result else {
      return XCTFail("Expected curated result.")
    }
    XCTAssertEqual(curated.map(\.candidateID), ["study", "case"])
    XCTAssertFalse(curated.contains { $0.candidateID == "totally-new-word" })
  }

  func testDeduplicatesRepeatedCandidateIDs() {
    let assessments = [
      Self.entry(id: "study", isRecommended: true, score: 9),
      Self.entry(id: "study", isRecommended: false, score: 3),
    ]

    let result = FoundationModelsCandidateCurator.validated(
      assessments,
      knownIDs: ["study"]
    )

    guard case .curated(let curated) = result else {
      return XCTFail("Expected curated result.")
    }
    XCTAssertEqual(curated.count, 1)
    XCTAssertTrue(curated[0].isRecommended)
  }

  func testInvalidScoresAndEmptyReasonsAreIgnored() {
    let assessments = [
      Self.entry(id: "study", isRecommended: true, score: 0),
      Self.entry(id: "case", isRecommended: true, score: 11),
      Self.entry(id: "chapter", isRecommended: true, score: 7, reason: ""),
    ]

    let result = FoundationModelsCandidateCurator.validated(
      assessments,
      knownIDs: ["study", "case", "chapter"]
    )

    XCTAssertEqual(result, .failed)
  }

  func testEmptyAssessmentListFailsInsteadOfUnfiltering() {
    let result = FoundationModelsCandidateCurator.validated(
      [],
      knownIDs: ["study"]
    )
    XCTAssertEqual(result, .failed)
  }

  func testWhitespaceContextualMeaningIsNormalized() {
    let result = FoundationModelsCandidateCurator.validated(
      [Self.entry(id: "study", isRecommended: true, score: 8, meaning: "  学习  ")],
      knownIDs: ["study"]
    )
    guard case .curated(let curated) = result else {
      return XCTFail("Expected curated result.")
    }
    XCTAssertEqual(curated[0].contextualMeaning, "学习")
  }

  // MARK: - Context boundaries

  func testEmptyContextReturnsFailedWithoutCallingModel() async {
    let curator = FoundationModelsCandidateCurator(
      model: .default,
      timeout: .seconds(1)
    )
    let emptyContext = ImportCandidateCurationContext(sourceText: "  ", candidateIDs: ["study"])
    let emptyIDs = ImportCandidateCurationContext(sourceText: "study", candidateIDs: [])

    let emptyTextResult = await curator.assess(
      candidates: [],
      context: emptyContext
    )
    let emptyIDResult = await curator.assess(
      candidates: [],
      context: emptyIDs
    )

    XCTAssertEqual(emptyTextResult, .failed)
    XCTAssertEqual(emptyIDResult, .failed)
  }

  func testCurationContextTrimsAndFiltersEmptyIDs() {
    let context = ImportCandidateCurationContext(
      sourceText: "  Study the case.  ",
      candidateIDs: ["study", "", "case"]
    )

    XCTAssertFalse(context.isEmpty)
    XCTAssertEqual(context.sourceText, "Study the case.")
    XCTAssertEqual(context.candidateIDs, ["study", "case"])
  }

  func testEmptyContextDetection() {
    XCTAssertTrue(
      ImportCandidateCurationContext(sourceText: "", candidateIDs: []).isEmpty
    )
    XCTAssertFalse(
      ImportCandidateCurationContext(sourceText: "text", candidateIDs: ["id"]).isEmpty
    )
  }

  // MARK: - Result invariants

  func testFailedResultIsEquatableAndNeverCarriesWords() {
    let result = ImportCandidateCurationResult.failed
    XCTAssertEqual(result, .failed)

    guard case .failed = result else {
      return XCTFail("Expected failure state.")
    }
  }

  func testCuratedAssessmentCannotExposeNewWordsInModel() {
    let assessment = ImportCandidateAssessment(
      candidateID: "study",
      isRecommended: true,
      valueScore: 8,
      shortReason: "学术语境",
      contextualMeaning: "研究"
    )
    XCTAssertEqual(assessment.candidateID, "study")
    XCTAssertTrue(assessment.isRecommended)
    XCTAssertEqual(assessment.valueScore, 8)
  }

  // MARK: - Fixtures

  private static func entry(
    id: String,
    isRecommended: Bool,
    score: Int,
    reason: String = "语义判断",
    meaning: String? = nil,
    isFunctionWord: Bool = false
  ) -> FoundationCandidateAssessmentEntry {
    FoundationCandidateAssessmentEntry(
      candidateID: id,
      isRecommended: isRecommended,
      valueScore: score,
      isFunctionWord: isFunctionWord,
      shortReason: reason,
      contextualMeaning: meaning
    )
  }

  private static func makeEntries(
    _ entries: [FoundationCandidateAssessmentEntry]
  ) -> [FoundationCandidateAssessmentEntry] {
    entries
  }
}
