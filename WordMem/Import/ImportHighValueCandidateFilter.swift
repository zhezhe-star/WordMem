import Foundation

/// Deterministic filtering applied before dictionary advice and chip
/// translation. The filter intentionally favors vocabulary worth learning and
/// excludes function words, single letters, and short domain fragments.
enum ImportHighValueCandidateFilter {
  private static let functionWords: Set<String> = [
    "a", "an", "the", "and", "or", "but", "nor", "so", "yet", "if", "as",
    "because", "although", "while", "until", "than", "that", "which", "who",
    "whom", "whose", "when", "where", "i", "me", "my", "mine", "you", "your",
    "yours", "he", "him", "his", "she", "her", "hers", "it", "its", "we",
    "us", "our", "ours", "they", "them", "their", "theirs", "this", "these",
    "that", "those", "am", "is", "are", "was", "were", "be", "been", "being",
    "do", "does", "did", "have", "has", "had", "will", "would", "shall",
    "should", "can", "could", "may", "might", "must", "of", "to", "in", "on",
    "at", "by", "for", "with", "about", "against", "between", "into", "onto",
    "from", "up", "down", "out", "off", "over", "under", "again", "then",
    "here", "there", "not", "no", "yes",
  ]

  private static let domainFragments: Set<String> = [
    "com", "net", "org", "edu", "gov", "www", "http", "https",
  ]

  static func highValueCandidates(
    from candidates: [WordImportCandidate]
  ) -> [WordImportCandidate] {
    candidates.filter { isHighValue($0.normalizedKey) }
  }

  static func isHighValue(_ normalizedKey: String) -> Bool {
    let key =
      normalizedKey
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .lowercased()
      .replacingOccurrences(of: "'", with: "")
    guard !key.isEmpty, key.count > 2 else { return false }
    return !functionWords.contains(key) && !domainFragments.contains(key)
  }
}
