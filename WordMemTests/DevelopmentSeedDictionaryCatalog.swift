@testable import WordMem
import Foundation

enum DevelopmentSeedDictionaryCatalog {
    static let version = "seed-2026.10-mvp"

    static let entries: [DictionaryEntry] = [
        DictionaryEntry(
            id: "beautiful",
            headword: "beautiful",
            normalizedKey: "beautiful",
            phonetic: "/ˈbjuːtɪfl/",
            senses: [
                WordSense(partOfSpeech: "adj.", chinese: "美丽的", english: "pleasing to look at"),
                WordSense(partOfSpeech: "adj.", chinese: "很好的", english: "very good"),
            ],
            forms: [
                WordForm(kind: .adverb, value: "beautifully"),
                WordForm(kind: .verb, value: "beautify"),
            ],
            tags: ["CET4", "CET6", "考研"],
            frequencyRank: 780,
            dictionaryVersion: version
        ),
        DictionaryEntry(
            id: "give",
            headword: "give",
            normalizedKey: "give",
            phonetic: "/ɡɪv/",
            senses: [
                WordSense(partOfSpeech: "v.", chinese: "给；交给", english: "to hand something to someone"),
                WordSense(partOfSpeech: "v.", chinese: "提供；引起", english: "to provide or cause"),
            ],
            forms: [
                WordForm(kind: .pastTense, value: "gave"),
                WordForm(kind: .pastParticiple, value: "given"),
                WordForm(kind: .presentParticiple, value: "giving"),
                WordForm(kind: .thirdPersonSingular, value: "gives"),
            ],
            tags: ["CET4", "CET6", "高考"],
            frequencyRank: 105,
            dictionaryVersion: version
        ),
        DictionaryEntry(
            id: "run",
            headword: "run",
            normalizedKey: "run",
            phonetic: "/rʌn/",
            senses: [
                WordSense(partOfSpeech: "v.", chinese: "跑；奔跑", english: "to move quickly on foot"),
                WordSense(partOfSpeech: "n.", chinese: "跑步；一段运行", english: "an act of running"),
            ],
            forms: [
                WordForm(kind: .pastTense, value: "ran"),
                WordForm(kind: .pastParticiple, value: "run"),
                WordForm(kind: .presentParticiple, value: "running"),
                WordForm(kind: .thirdPersonSingular, value: "runs"),
            ],
            tags: ["CET4", "CET6", "高考"],
            frequencyRank: 180,
            dictionaryVersion: version
        ),
        DictionaryEntry(
            id: "tooth",
            headword: "tooth",
            normalizedKey: "tooth",
            phonetic: "/tuːθ/",
            senses: [
                WordSense(partOfSpeech: "n.", chinese: "牙齿", english: "one of the hard white objects in the mouth"),
            ],
            forms: [WordForm(kind: .plural, value: "teeth")],
            tags: ["CET4", "高考"],
            frequencyRank: 2450,
            dictionaryVersion: version
        ),
        DictionaryEntry(
            id: "serendipity",
            headword: "serendipity",
            normalizedKey: "serendipity",
            phonetic: "/ˌserənˈdɪpəti/",
            senses: [
                WordSense(
                    partOfSpeech: "n.",
                    chinese: "意外发现新事物的能力",
                    english: "the occurrence of valuable discoveries by chance"
                ),
            ],
            forms: [],
            tags: ["GRE", "SAT"],
            frequencyRank: 21800,
            dictionaryVersion: version
        ),
    ]
}
