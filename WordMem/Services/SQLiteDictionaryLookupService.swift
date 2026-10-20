import Foundation
import SQLite3

private let SQLITE_TRANSIENT = unsafeBitCast(
    OpaquePointer(bitPattern: -1),
    to: sqlite3_destructor_type.self
)

enum DictionaryServiceError: Error {
    case databaseNotFound
    case cannotOpen(String)
    case queryFailed(String)
    case invalidResource(String)
}

actor SQLiteDictionaryLookupService: DictionaryLookupService {
    nonisolated private let databaseURL: URL
    nonisolated(unsafe) private var database: OpaquePointer?
    private var dictionaryVersion = "unknown"
    private var curatedLemmaPriorityKeys: Set<String> = []

    init(databaseURL: URL) throws {
        self.databaseURL = databaseURL
        var database: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX
        guard sqlite3_open_v2(databaseURL.path, &database, flags, nil) == SQLITE_OK else {
            let message = database.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown error"
            sqlite3_close_v2(database)
            throw DictionaryServiceError.cannotOpen(message)
        }

        self.database = database
        let metadata = try Self.readMetadata(database: database)
        try Self.validate(metadata)
        dictionaryVersion = metadata["sourceRevision"] ?? "unknown"
        curatedLemmaPriorityKeys = Set(
            (metadata["curatedLemmaPriorityKeys"] ?? "")
                .split(separator: ",")
                .map(String.init)
        )
    }

    init(bundle: Bundle = Bundle(for: WordEntry.self)) throws {
        guard let url = Self.databaseURL(bundle: bundle) else {
            throw DictionaryServiceError.databaseNotFound
        }

        try self.init(databaseURL: url)
    }

    nonisolated deinit {
        sqlite3_close_v2(database)
    }

    static func databaseURL(bundle: Bundle = Bundle(for: WordEntry.self)) -> URL? {
        bundle.url(forResource: "Dictionary", withExtension: "sqlite")
    }

    static func metadata(bundle: Bundle = Bundle(for: WordEntry.self)) async throws -> [String: String] {
        let service = try SQLiteDictionaryLookupService(bundle: bundle)
        return try await service.metadata()
    }

    private static func readMetadata(database: OpaquePointer?) throws -> [String: String] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(
            database,
            "select key, value from dictionary_meta order by key",
            -1,
            &statement,
            nil
        ) == SQLITE_OK else {
            throw DictionaryServiceError.queryFailed(String(cString: sqlite3_errmsg(database)))
        }
        defer { sqlite3_finalize(statement) }

        var metadata: [String: String] = [:]
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let key = sqlite3_column_text(statement, 0),
                  let value = sqlite3_column_text(statement, 1) else { continue }
            metadata[String(cString: key)] = String(cString: value)
        }
        return metadata
    }

    private static func validate(_ metadata: [String: String]) throws {
        let requiredKeys = [
            "pipelineVersion", "schemaVersion", "source", "sourceRevision",
            "sourceLicense", "selection", "entryCount", "lemmaCount",
            "wordFormCount", "sourceCsvSHA256", "sourceLemmaSHA256",
            "sourceLicenseSHA256",
        ]
        for key in requiredKeys where metadata[key]?.isEmpty != false {
            throw DictionaryServiceError.invalidResource("Missing metadata: \(key)")
        }

        guard metadata["schemaVersion"] == "1",
              metadata["pipelineVersion"] == "3",
              metadata["source"] == "ECDICT",
              metadata["sourceLicense"] == "MIT",
              metadata["sourceRevision"] != "unknown",
              let entryCount = Int(metadata["entryCount"] ?? ""), entryCount > 0,
              let lemmaCount = Int(metadata["lemmaCount"] ?? ""), lemmaCount > 0,
              let formCount = Int(metadata["wordFormCount"] ?? ""), formCount > 0 else {
            throw DictionaryServiceError.invalidResource("Unsupported or incomplete dictionary resource")
        }
    }

    func lookup(_ rawInput: String) async throws -> DictionaryLookupResult {
        let key = WordInputNormalizer.normalizedKey(from: rawInput)
        guard !key.isEmpty else {
            return DictionaryLookupResult(originalInput: rawInput, status: .notFound, entry: nil)
        }

        if let exactEntry = try entry(normalizedKey: key) {
            let lemmaKey = try lemmaKey(for: key)
            if let lemmaKey,
               shouldResolveLemma(exactEntry: exactEntry, inputKey: key, lemmaKey: lemmaKey),
               let entry = try entry(normalizedKey: lemmaKey) {
                return DictionaryLookupResult(originalInput: rawInput, status: .lemmaResolved, entry: entry)
            }

            return DictionaryLookupResult(originalInput: rawInput, status: .enriched, entry: exactEntry)
        }

        if let lemmaKey = try lemmaKey(for: key),
           let entry = try entry(normalizedKey: lemmaKey) {
            return DictionaryLookupResult(originalInput: rawInput, status: .lemmaResolved, entry: entry)
        }

        let candidates = try closeMatchCandidates(for: key)
        let suggestions = candidates
            .map { (entry: $0, distance: levenshteinDistance(key, $0.normalizedKey)) }
            .filter { $0.distance > 0 }
            .sorted {
                if $0.distance != $1.distance { return $0.distance < $1.distance }
                return ($0.entry.frequencyRank ?? .max) < ($1.entry.frequencyRank ?? .max)
            }
            .map(\.entry)

        if let best = suggestions.first,
           isHighConfidenceCorrection(input: key, candidate: best.normalizedKey) {
            return DictionaryLookupResult(
                originalInput: rawInput,
                status: .autoCorrected,
                entry: best
            )
        }

        return DictionaryLookupResult(
            originalInput: rawInput,
            status: .notFound,
            entry: bareEntry(rawInput: rawInput, key: key),
            suggestions: suggestions
        )
    }

    func metadata() throws -> [String: String] {
        let statement = try prepare(
            sql: "select key, value from dictionary_meta order by key"
        )
        defer { sqlite3_finalize(statement) }

        var metadata: [String: String] = [:]
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let key = sqlite3_column_text(statement, 0),
                  let value = sqlite3_column_text(statement, 1) else { continue }
            metadata[String(cString: key)] = String(cString: value)
        }

        try checkStep()
        return metadata
    }

    private func entry(normalizedKey key: String) throws -> DictionaryEntry? {
        let statement = try prepare(
            sql: """
            select normalized_word, word, phonetic, translation, definition,
                   exchange, tags, rank
            from entries
            where normalized_word = ?
            limit 1
            """
        )
        defer { sqlite3_finalize(statement) }
        try bind(key, to: statement, index: 1)

        guard sqlite3_step(statement) == SQLITE_ROW else {
            try checkStep()
            return nil
        }

        return try dictionaryEntry(from: statement)
    }

    private func lemmaKey(for key: String) throws -> String? {
        let statement = try prepare(
            sql: "select normalized_lemma from lemma_lookup where input_key = ? limit 1"
        )
        defer { sqlite3_finalize(statement) }
        try bind(key, to: statement, index: 1)

        guard sqlite3_step(statement) == SQLITE_ROW else {
            try checkStep()
            return nil
        }

        guard let lemma = sqlite3_column_text(statement, 0) else { return nil }
        return String(cString: lemma)
    }

    private func wordForms(for lemmaKey: String) throws -> [WordForm] {
        let statement = try prepare(
            sql: """
            select kind, value
            from forms
            where normalized_lemma = ?
            order by normalized_form
            """
        )
        defer { sqlite3_finalize(statement) }
        try bind(lemmaKey, to: statement, index: 1)

        var forms: [WordForm] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let rawKind = string(statement, 0)
            let value = string(statement, 1)
            guard let kind = WordForm.Kind(rawValue: rawKind) else { continue }
            forms.append(WordForm(kind: kind, value: value))
        }

        try checkStep()
        return forms
    }

    private func closeMatchCandidates(for key: String) throws -> [DictionaryEntry] {
        let firstLetter = key.first.map(String.init)?.lowercased() ?? key
        let upperBound = Self.upperBound(forPrefix: firstLetter)
        let length = key.count
        let statement = try prepare(
            sql: """
            select normalized_word, word, phonetic, translation, definition,
                   exchange, tags, rank
            from entries
            where normalized_word >= ? and normalized_word < ?
              and length(normalized_word) between ? and ?
            order by rank
            limit 2048
            """
        )
        defer { sqlite3_finalize(statement) }

        try bind(firstLetter, to: statement, index: 1)
        try bind(upperBound, to: statement, index: 2)
        try bind(Int64(max(1, length - 2)), to: statement, index: 3)
        try bind(Int64(length + 2), to: statement, index: 4)

        var entries: [DictionaryEntry] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            entries.append(try dictionaryEntry(from: statement))
        }
        try checkStep()
        return entries
    }

    private func bind(_ value: String, to statement: OpaquePointer?, index: Int32) throws {
        guard sqlite3_bind_text(statement, index, value, -1, SQLITE_TRANSIENT) == SQLITE_OK else {
            throw DictionaryServiceError.queryFailed(lastErrorMessage())
        }
    }

    private func bind(_ value: Int64, to statement: OpaquePointer?, index: Int32) throws {
        guard sqlite3_bind_int64(statement, index, value) == SQLITE_OK else {
            throw DictionaryServiceError.queryFailed(lastErrorMessage())
        }
    }

    private func shouldResolveLemma(
        exactEntry: DictionaryEntry,
        inputKey: String,
        lemmaKey: String
    ) -> Bool {
        guard let rank = exactEntry.frequencyRank else { return true }

        // High-ranking ECDICT words often have independent meanings
        // (number, meeting, saw). Preserve them rather than rewriting to a lemma.
        if rank <= 1_000 { return false }

        // Curated cases cover explicit product requirements without using a
        // spelling heuristic that rewrites independent -ing nouns.
        if rank >= 900_000 { return true }
        if curatedLemmaPriorityKeys.contains(inputKey) { return true }

        return false
    }

    private static func upperBound(forPrefix prefix: String) -> String {
        guard let character = prefix.first,
              let asciiValue = character.asciiValue,
              asciiValue >= ("a" as Character).asciiValue ?? 97,
              asciiValue < ("z" as Character).asciiValue ?? 122 else {
            return prefix + "\u{FFFF}"
        }

        let nextScalar = asciiValue + 1
        return String(UnicodeScalar(nextScalar))
    }

    private func dictionaryEntry(from statement: OpaquePointer?) throws -> DictionaryEntry {
        let key = string(statement, 0)
        let headword = string(statement, 1)
        let phonetic = optionalString(statement, 2)
        let translation = string(statement, 3)
        let definition = optionalString(statement, 4)
        let tags = string(statement, 6)
            .split(separator: " ")
            .map(String.init)
        let rank = Int(sqlite3_column_int64(statement, 7))

        return DictionaryEntry(
            id: "ecdict.\(dictionaryVersion).\(key)",
            headword: headword,
            normalizedKey: key,
            phonetic: phonetic,
            senses: Self.senses(translation: translation, definition: definition),
            forms: try wordForms(for: key),
            tags: tags,
            frequencyRank: rank,
            dictionaryVersion: dictionaryVersion
        )
    }

    private func bareEntry(rawInput: String, key: String) -> DictionaryEntry {
        DictionaryEntry(
            id: "user.\(key)",
            headword: rawInput.trimmingCharacters(in: .whitespacesAndNewlines),
            normalizedKey: key,
            phonetic: nil,
            senses: [],
            forms: [],
            tags: [],
            frequencyRank: nil,
            dictionaryVersion: dictionaryVersion
        )
    }

    private static func senses(
        translation: String,
        definition: String?
    ) -> [WordSense] {
        var englishByPartOfSpeech: [String: String] = [:]
        for line in parseLines(definition ?? "") {
            let parsed = parsedSenseLine(line)
            if let partOfSpeech = parsed.partOfSpeech {
                englishByPartOfSpeech[partOfSpeech] = parsed.chinese
            }
        }

        let senses = parseLines(translation).map { line -> WordSense in
            let parsed = parsedSenseLine(line)
            let english = parsed.partOfSpeech.flatMap { englishByPartOfSpeech[$0] }
            return WordSense(
                partOfSpeech: parsed.partOfSpeech,
                chinese: parsed.chinese,
                english: english
            )
        }

        return senses.isEmpty
            ? [WordSense(partOfSpeech: nil, chinese: translation, english: nil)]
            : senses
    }

    private static func parseLines(_ raw: String) -> [String] {
        raw.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    private static func parsedSenseLine(_ line: String) -> (partOfSpeech: String?, chinese: String) {
        let partOfSpeechWords = [
            "n.", "v.", "adj.", "adv.", "prep.", "pron.",
            "conj.", "interj.", "art.", "num.", "aux.",
        ]

        for partOfSpeech in partOfSpeechWords where line.hasPrefix(partOfSpeech) {
            let meaning = line.dropFirst(partOfSpeech.count)
                .trimmingCharacters(in: .whitespaces)
            return (partOfSpeech, meaning.isEmpty ? line : meaning)
        }

        return (nil, line)
    }

    private func prepare(sql: String) throws -> OpaquePointer? {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
            throw DictionaryServiceError.queryFailed(lastErrorMessage())
        }
        return statement
    }

    private func checkStep() throws {
        let code = sqlite3_errcode(database)
        guard code == SQLITE_OK || code == SQLITE_DONE else {
            throw DictionaryServiceError.queryFailed(lastErrorMessage())
        }
    }

    private func lastErrorMessage() -> String {
        String(cString: sqlite3_errmsg(database))
    }

    private func string(_ statement: OpaquePointer?, _ index: Int32) -> String {
        optionalString(statement, index) ?? ""
    }

    private func optionalString(_ statement: OpaquePointer?, _ index: Int32) -> String? {
        guard let text = sqlite3_column_text(statement, index) else { return nil }
        return String(cString: text)
    }

    private func isHighConfidenceCorrection(input: String, candidate: String) -> Bool {
        let distance = levenshteinDistance(input, candidate)
        let allowedDistance = input.count < 4 ? 0 : input.count < 7 ? 1 : 2
        return distance > 0 && distance <= allowedDistance
    }

    private func levenshteinDistance(_ lhs: String, _ rhs: String) -> Int {
        let left = Array(lhs)
        let right = Array(rhs)
        guard !left.isEmpty else { return right.count }
        guard !right.isEmpty else { return left.count }

        var previous = Array(0...right.count)
        var current = [Int](repeating: 0, count: right.count + 1)

        for leftIndex in 1...left.count {
            current[0] = leftIndex
            for rightIndex in 1...right.count {
                let cost = left[leftIndex - 1] == right[rightIndex - 1] ? 0 : 1
                current[rightIndex] = min(
                    previous[rightIndex] + 1,
                    current[rightIndex - 1] + 1,
                    previous[rightIndex - 1] + cost
                )
            }
            swap(&previous, &current)
        }

        return previous[right.count]
    }
}
