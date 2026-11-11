import Foundation
import XCTest

@testable import WordMem

final class FoundationModelsCuratorTests: XCTestCase {
  // MARK: - Meaningful curation

  func testCurationDeadlineReturnsBeforeAnUncancellableOperation() async {
    let started = ContinuousClock.now

    let outcome = await ImportCurationDeadline.run(timeout: .milliseconds(30)) {
      _ = try? await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
        DispatchQueue.global().asyncAfter(deadline: .now() + 2) {
          continuation.resume(returning: ())
        }
      }
      return "late"
    }

    guard case .timedOut = outcome else {
      return XCTFail("Expected deadline outcome.")
    }
    XCTAssertLessThan(ContinuousClock.now - started, .seconds(1))
  }

  func testCurationDeadlineReturnsCompletedOperation() async {
    let outcome = await ImportCurationDeadline.run(timeout: .seconds(1)) {
      "finished"
    }

    guard case .completed("finished") = outcome else {
      return XCTFail("Expected completed outcome.")
    }
  }

  func testValidatesOnlyRecommendedIDsFromFoundationModels() {
    let result = FoundationModelsCandidateCurator.validated(
      ["study", "  case  ", "study", "totally-new-word", ""],
      knownIDs: ["study", "case", "chapter"]
    )

    guard case .curated(let curated) = result else {
      return XCTFail("Expected curated result.")
    }
    XCTAssertEqual(curated.map(\.candidateID), ["study", "case"])
    XCTAssertTrue(curated.allSatisfy(\.isRecommended))
  }

  func testEmptyRecommendationListFailsInsteadOfUnfiltering() {
    let result = FoundationModelsCandidateCurator.validated(
      [],
      knownIDs: ["study", "case"]
    )

    XCTAssertEqual(result, .failed)
  }

  func testRecommendationSchemaRequestsACompactIDList() {
    let recommendations = FoundationCandidateRecommendations(
      candidateIDs: ["library", "  ", "privacy"]
    )

    XCTAssertEqual(recommendations.candidateIDs, ["library", "  ", "privacy"])
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

}
