import SwiftUI
import AVFoundation

struct Word: Identifiable {
    let id = UUID()
    let word: String
    let pronunciation: String
    let definition: String
    let example: String
    let meaning: String
    let tags: [String]

    init(word: String, pronunciation: String, definition: String, example: String, meaning: String, tags: [String]) {
        self.word = word
        self.pronunciation = pronunciation
        self.definition = definition
        self.example = example
        self.meaning = meaning
        self.tags = tags
    }
}

struct WordDetailView: View {
    let word: Word
    @State private var synthesizer = AVSpeechSynthesizer()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Word and pronunciation section
                VStack(alignment: .leading, spacing: 10) {
                    Text(word.word)
                        .font(.system(size: 32, weight: .bold))
                        .foregroundColor(.blue)

                    Text(word.pronunciation)
                        .font(.title3)
                        .foregroundColor(.secondary)

                    if !word.meaning.isEmpty {
                        Text(word.meaning)
                            .font(.title3)
                            .foregroundColor(.primary)
                    }

                    if !word.tags.isEmpty {
                        HStack {
                            ForEach(word.tags, id: \.self) { tag in
                                Text(tag)
                                    .font(.caption)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.blue.opacity(0.2))
                                    .foregroundColor(.blue)
                                    .cornerRadius(8)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(Color.blue.opacity(0.1))
                .cornerRadius(12)

                // Play button
                Button(action: playWord) {
                    HStack {
                        Image(systemName: "speaker.wave.2.fill")
                            .font(.title2)
                        Text("Play Pronunciation")
                            .font(.headline)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(12)
                }
                .padding(.vertical)

                // Definition section
                VStack(alignment: .leading, spacing: 8) {
                    Text("Definition")
                        .font(.headline)
                        .foregroundColor(.primary)

                    Text(word.definition)
                        .font(.body)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(Color.gray.opacity(0.1))
                .cornerRadius(12)

                // Example section
                VStack(alignment: .leading, spacing: 8) {
                    Text("Example")
                        .font(.headline)
                        .foregroundColor(.primary)

                    Text("\"\(word.example)\"")
                        .font(.body)
                        .italic()
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(Color.gray.opacity(0.1))
                .cornerRadius(12)
            }
            .padding()
        }
        .navigationTitle("Word Detail")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func playWord() {
        let utterance = AVSpeechUtterance(string: word.word)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = 0.5
        utterance.pitchMultiplier = 1.0

        synthesizer.speak(utterance)
    }
}

struct ContentView: View {
    let words: [Word] = [
        Word(word: "ephemeral", pronunciation: "/əˈfem(ə)rəl/", definition: "lasting for a very short time", example: "Fashions are ephemeral, changing with every season.", meaning: "短暂的", tags: ["adj."]),
        Word(word: "serendipity", pronunciation: "/ˌserənˈdipədē/", definition: "the occurrence of events by chance in a happy way", example: "It was pure serendipity that we met at the coffee shop.", meaning: "意外发现的好运", tags: ["n."]),
        Word(word: "eloquent", pronunciation: "/ˈeləkwənt/", definition: "fluent or persuasive in speaking or writing", example: "She gave an eloquent speech that moved the audience.", meaning: "雄辩的", tags: ["adj."]),
        Word(word: "resilient", pronunciation: "/rəˈzilyənt/", definition: "able to recover quickly from difficulties", example: "Children are often more resilient than adults expect.", meaning: "有弹性的", tags: ["adj."]),
        Word(word: "ubiquitous", pronunciation: "/yo͞oˈbikwədəs/", definition: "present, appearing, or found everywhere", example: "Smartphones have become ubiquitous in modern society.", meaning: "无处不在的", tags: ["adj."])
    ]

    var body: some View {
        NavigationView {
            List(words) { word in
                NavigationLink(destination: WordDetailView(word: word)) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(word.word)
                                .font(.headline)
                                .foregroundColor(.blue)

                            Spacer()

                            Image(systemName: "speaker.wave.2.fill")
                                .foregroundColor(.blue)
                                .font(.caption)
                        }

                        Text(word.pronunciation)
                            .font(.caption)
                            .foregroundColor(.secondary)

                        if !word.meaning.isEmpty {
                            Text(word.meaning)
                                .font(.caption)
                                .foregroundColor(.primary)
                        }

                        Text(word.definition)
                            .font(.subheadline)
                            .foregroundColor(.primary)
                            .lineLimit(2)
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle("WordMem")
            .navigationBarTitleDisplayMode(.large)
        }
    }
}

#Preview {
    ContentView()
}
