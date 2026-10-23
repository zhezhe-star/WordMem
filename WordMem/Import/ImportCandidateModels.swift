import Foundation

/// A target-independent representation of one selectable source token.
struct ImportCandidateChip: Identifiable, Hashable, Sendable {
    let id: String
    let text: String
    let detail: String?
    let sourceOrder: Int
    let group: String?

    init(
        id: String,
        text: String,
        detail: String? = nil,
        sourceOrder: Int,
        group: String? = nil
    ) {
        self.id = id
        self.text = text
        self.detail = detail
        self.sourceOrder = sourceOrder
        self.group = group
    }
}

extension ImportCandidateChip {
    /// Keeps the first appearance of every identity so reusable views cannot
    /// crash on duplicate IDs and stable source order remains predictable.
    static func uniquelyIdentified(_ chips: [ImportCandidateChip]) -> [ImportCandidateChip] {
        var seenIDs = Set<String>()
        return chips.filter { seenIDs.insert($0.id).inserted }
    }
}

enum ImportCandidateAccessibility {
    static func label(text: String, meaning: String?) -> String {
        let trimmedMeaning = meaning?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmedMeaning.isEmpty ? text : "\(text)，\(trimmedMeaning)"
    }
}

/// `Text` has no public wrapped-line count, so long unwrapped paragraphs use a
/// conservative character threshold in addition to explicit line breaks.
struct ImportContextExpansion: Equatable {
    let isExpandable: Bool
    private(set) var isExpanded = false

    init(text: String, collapsedLineLimit: Int = 5, wrappedCharacterLimit: Int = 220) {
        let lineCount = text.components(separatedBy: .newlines).count
        isExpandable = lineCount > collapsedLineLimit || text.count > wrappedCharacterLimit
    }

    var lineLimit: Int? {
        isExpandable && !isExpanded ? 5 : nil
    }

    mutating func toggle() {
        guard isExpandable else { return }
        isExpanded.toggle()
    }
}

struct ImportCandidateSection: Identifiable, Hashable, Sendable {
    let title: String?
    let chips: [ImportCandidateChip]

    var id: String { title ?? "" }
}

enum ImportCandidateOrganizer {
    /// Preserves original reading order and groups only when a caller supplies
    /// group metadata, so 50+ chips stay predictable without list rebuilds.
    static func sections(from chips: [ImportCandidateChip]) -> [ImportCandidateSection] {
        let orderedChips = chips.sorted { $0.sourceOrder < $1.sourceOrder }
        var groupedChips: [String: [ImportCandidateChip]] = [:]
        var groupOrder: [String] = []

        for chip in orderedChips {
            let group = chip.group ?? "全部"
            if groupedChips[group] == nil {
                groupOrder.append(group)
            }
            groupedChips[group, default: []].append(chip)
        }

        return groupOrder.map { title in
            ImportCandidateSection(
                title: groupOrder.count == 1 && title == "全部" ? nil : title,
                chips: groupedChips[title] ?? []
            )
        }
    }
}

/// Stores selection as exclusions when a caller wants every candidate selected
/// initially. Selected results always follow `chips` source order.
struct ImportChipSelection: Equatable, Sendable {
    private var orderedIDs: [String]
    private var chipsByID: [String: ImportCandidateChip]
    private var selectedIDs: Set<String>

    init(chips: [ImportCandidateChip], selectsAllByDefault: Bool = true) {
        let uniqueChips = ImportCandidateChip.uniquelyIdentified(chips)
        orderedIDs = uniqueChips.map(\.id)
        chipsByID = Dictionary(uniqueKeysWithValues: uniqueChips.map { ($0.id, $0) })
        selectedIDs = selectsAllByDefault ? Set(orderedIDs) : []
    }

    var selectedCount: Int { selectedIDs.count }

    var selectedChips: [ImportCandidateChip] {
        orderedIDs.compactMap { id in
            selectedIDs.contains(id) ? chipsByID[id] : nil
        }
    }

    func isSelected(_ id: String) -> Bool {
        selectedIDs.contains(id)
    }

    mutating func select(_ id: String) {
        guard orderedIDs.contains(id) else { return }
        selectedIDs.insert(id)
    }

    mutating func deselect(_ id: String) {
        selectedIDs.remove(id)
    }

    mutating func toggle(_ id: String) {
        if isSelected(id) {
            deselect(id)
        } else {
            select(id)
        }
    }

    mutating func selectAll() {
        selectedIDs = Set(orderedIDs)
    }

    mutating func clear() {
        selectedIDs = []
    }

    mutating func updateChips(_ chips: [ImportCandidateChip]) {
        let oldDeselectedIDs = Set(orderedIDs).subtracting(selectedIDs)
        let uniqueChips = ImportCandidateChip.uniquelyIdentified(chips)
        orderedIDs = uniqueChips.map(\.id)
        chipsByID = Dictionary(uniqueKeysWithValues: uniqueChips.map { ($0.id, $0) })
        selectedIDs = selectedIDs.intersection(orderedIDs).union(orderedIDs).subtracting(oldDeselectedIDs)
    }

}
