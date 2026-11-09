import Foundation
import FoundationModels

/// Bounded context given to a semantic candidate curator. It carries only
/// the review document text and deterministic candidate identities already
/// extracted by the app, so the model can never introduce new words.
struct ImportCandidateCurationContext: Equatable, Sendable {
  let sourceText: String
  let candidateIDs: [String]

  init(sourceText: String, candidateIDs: [String]) {
    self.sourceText = sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
    self.candidateIDs = candidateIDs.filter { !$0.isEmpty }
  }

  var isEmpty: Bool {
    sourceText.isEmpty || candidateIDs.isEmpty
  }
}

/// One structured assessment for an existing candidate identity. The word
/// itself is intentionally absent so the model can only rank known IDs.
struct ImportCandidateAssessment: Equatable, Sendable {
  let candidateID: String
  let isRecommended: Bool
  let valueScore: Int
  let shortReason: String
  let contextualMeaning: String?
}

/// Outcome of one curation pass. `.failed` always maps to a user-facing
/// no-candidates state; it never falls back to an unfiltered word list.
enum ImportCandidateCurationResult: Equatable, Sendable {
  case curated([ImportCandidateAssessment])
  case failed
}

/// App-side abstraction replacing deterministic candidate filtering. The
/// implementation decides whether semantic curation is possible, but it must
/// never substitute another hardcoded vocabulary gate for the model.
protocol ImportCandidateCurating: Sendable {
  func assess(
    candidates: [WordImportCandidate],
    context: ImportCandidateCurationContext
  ) async -> ImportCandidateCurationResult
}

/// Structured output shape requested from Foundation Models.
@Generable
struct FoundationCandidateAssessmentEntry {
  @Guide(description: "Exact candidate identifier copied from the input list")
  var candidateID: String
  @Guide(description: "Whether this word is worth learning from this content")
  var isRecommended: Bool
  @Guide(description: "Learning value from 1 to 10")
  var valueScore: Int
  @Guide(description: "One short Simplified Chinese reason")
  var shortReason: String
  @Guide(description: "Meaning in this content, optional")
  var contextualMeaning: String?
}

@Generable
struct FoundationCandidateAssessment {
  @Guide(description: "One assessment per requested candidate")
  var assessments: [FoundationCandidateAssessmentEntry]
}

/// iOS 26+ Foundation Models implementation. Every failure mode resolves to
/// `.failed` so the review screen can show an actionable empty state while a
/// finished document translation stays visible.
struct FoundationModelsCandidateCurator: ImportCandidateCurating {
  private let model: SystemLanguageModel
  private let timeout: Duration
  private let maximumCandidates: Int

  init(
    model: SystemLanguageModel = .default,
    timeout: Duration = .seconds(10),
    maximumCandidates: Int = 120
  ) {
    self.model = model
    self.timeout = timeout
    self.maximumCandidates = max(1, maximumCandidates)
  }

  func assess(
    candidates: [WordImportCandidate],
    context: ImportCandidateCurationContext
  ) async -> ImportCandidateCurationResult {
    guard model.isAvailable, !context.isEmpty else { return .failed }

    let knownIDs = Set(context.candidateIDs)
    let boundedIDs = context.candidateIDs.prefix(maximumCandidates)
    guard !boundedIDs.isEmpty else { return .failed }

    let session = LanguageModelSession(model: model)
    let prompt = Self.prompt(
      sourceText: context.sourceText,
      candidateIDs: Array(boundedIDs)
    )

    let curationTask = Task.detached {
      try await session.respond(
        to: prompt,
        generating: FoundationCandidateAssessment.self
      )
    }
    let timeoutTask = Task.detached {
      try await Task.sleep(for: self.timeout)
      curationTask.cancel()
    }

    defer {
      timeoutTask.cancel()
    }

    do {
      let response = try await curationTask.value
      return Self.validated(
        response.content.assessments,
        knownIDs: knownIDs
      )
    } catch is CancellationError {
      return .failed
    } catch {
      return .failed
    }
  }

  static func validated(
    _ assessments: [FoundationCandidateAssessmentEntry],
    knownIDs: Set<String>
  ) -> ImportCandidateCurationResult {
    var uniqueAssessments: [ImportCandidateAssessment] = []
    var seenIDs = Set<String>()

    for assessment in assessments {
      let id = assessment.candidateID
        .trimmingCharacters(in: .whitespacesAndNewlines)
      guard !id.isEmpty, knownIDs.contains(id), seenIDs.insert(id).inserted
      else { continue }
      guard (1...10).contains(assessment.valueScore), !assessment.shortReason.isEmpty
      else { continue }

      let meaning = assessment.contextualMeaning.map {
        $0.trimmingCharacters(in: .whitespacesAndNewlines)
      }
      let normalizedMeaning =
        (meaning?.isEmpty == false) ? meaning : nil

      uniqueAssessments.append(
        ImportCandidateAssessment(
          candidateID: id,
          isRecommended: assessment.isRecommended,
          valueScore: assessment.valueScore,
          shortReason: assessment.shortReason,
          contextualMeaning: normalizedMeaning
        )
      )
    }

    return uniqueAssessments.isEmpty ? .failed : .curated(uniqueAssessments)
  }

  private static func prompt(
    sourceText: String,
    candidateIDs: [String]
  ) -> String {
    """
    你是英文学习词表筛选助手。只评估下列候选词 ID，禁止新增、合并、\
    翻译拼写或输出列表之外的词。
    内容：
    \(sourceText)
    候选词 ID：
    \(candidateIDs.joined(separator: ", "))
    只返回结构化评估。不推荐普通功能词。
    """
  }
}
