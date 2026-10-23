import AVFAudio
import Foundation

// MARK: - Test seams

@MainActor
protocol PronunciationAudioSessionControlling: AnyObject {
    var category: AVAudioSession.Category { get }
    var categoryOptions: AVAudioSession.CategoryOptions { get }
    func setCategory(_ category: AVAudioSession.Category, options: AVAudioSession.CategoryOptions) throws
    func setActive(_ active: Bool, options: AVAudioSession.SetActiveOptions) throws
}

@MainActor
protocol PronunciationPlaybackDelegate: AnyObject {
    func pronunciationEngine(_ engine: any PronunciationSpeechEngine, didFinish utterance: AVSpeechUtterance)
    func pronunciationEngine(_ engine: any PronunciationSpeechEngine, didCancel utterance: AVSpeechUtterance)
}

@MainActor
protocol PronunciationSpeechEngine: AnyObject {
    var pronunciationDelegate: (any PronunciationPlaybackDelegate)? { get set }
    func speak(_ utterance: AVSpeechUtterance)
    func stopSpeaking(at boundary: AVSpeechBoundary) -> Bool
}

// MARK: - AVAudioSession adapter

final class SystemPronunciationAudioSession: PronunciationAudioSessionControlling {
    var category: AVAudioSession.Category { AVAudioSession.sharedInstance().category }

    var categoryOptions: AVAudioSession.CategoryOptions {
        AVAudioSession.sharedInstance().categoryOptions
    }

    func setCategory(_ category: AVAudioSession.Category, options: AVAudioSession.CategoryOptions) throws {
        try AVAudioSession.sharedInstance().setCategory(category, mode: .default, options: options)
    }

    func setActive(_ active: Bool, options: AVAudioSession.SetActiveOptions) throws {
        try AVAudioSession.sharedInstance().setActive(active, options: options)
    }
}

// MARK: - AVSpeechSynthesizer adapter

final class AVSpeechPronunciationEngine: NSObject, PronunciationSpeechEngine, @unchecked Sendable {
    weak var pronunciationDelegate: (any PronunciationPlaybackDelegate)?

    private let synthesizer = AVSpeechSynthesizer()

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func speak(_ utterance: AVSpeechUtterance) {
        synthesizer.speak(utterance)
    }

    func stopSpeaking(at boundary: AVSpeechBoundary) -> Bool {
        synthesizer.stopSpeaking(at: boundary)
    }
}

private struct UtteranceBox: @unchecked Sendable {
    let utterance: AVSpeechUtterance
}

extension AVSpeechPronunciationEngine: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didFinish utterance: AVSpeechUtterance
    ) {
        deliver(utterance) { delegate, engine, utterance in
            delegate.pronunciationEngine(engine, didFinish: utterance)
        }
    }

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didCancel utterance: AVSpeechUtterance
    ) {
        deliver(utterance) { delegate, engine, utterance in
            delegate.pronunciationEngine(engine, didCancel: utterance)
        }
    }

    nonisolated private func deliver(
        _ utterance: AVSpeechUtterance,
        _ event: @escaping @MainActor (any PronunciationPlaybackDelegate, AVSpeechPronunciationEngine, AVSpeechUtterance) -> Void
    ) {
        let box = UtteranceBox(utterance: utterance)
        Task { @MainActor [weak self] in
            guard let self, let delegate = self.pronunciationDelegate else { return }
            event(delegate, self, box.utterance)
        }
    }
}

// MARK: - Shared pronunciation player

/// Plays short English pronunciations while transiently ducking other audio.
/// The session is kept active for every queued/repeated pronunciation and is
/// released only after the last utterance reports completion or cancellation.
@MainActor
final class EnglishPronunciationPlayer: ObservableObject, PronunciationPlaybackDelegate {
    static let shared = EnglishPronunciationPlayer()

    @Published private(set) var isSpeaking = false
    private(set) var isAvailable = false

    private let audioSession: any PronunciationAudioSessionControlling
    private let speechEngine: any PronunciationSpeechEngine
    private var activeUtteranceIDs: Set<ObjectIdentifier> = []

    init(
        audioSession: any PronunciationAudioSessionControlling = SystemPronunciationAudioSession(),
        speechEngine: any PronunciationSpeechEngine = AVSpeechPronunciationEngine(),
        voiceProvider: @MainActor () -> AVSpeechSynthesisVoice? = {
            AVSpeechSynthesisVoice(language: "en-US")
        }
    ) {
        self.audioSession = audioSession
        self.speechEngine = speechEngine
        self.isAvailable = voiceProvider() != nil
        speechEngine.pronunciationDelegate = self
    }

    @discardableResult
    func play(_ text: String, rate: Float = 0.5) -> Bool {
        guard isAvailable, !text.isEmpty else { return false }

        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = rate

        let utteranceID = ObjectIdentifier(utterance)
        let shouldActivateSession = activeUtteranceIDs.isEmpty
        activeUtteranceIDs.insert(utteranceID)

        if shouldActivateSession {
            let priorCategory = audioSession.category
            let priorCategoryOptions = audioSession.categoryOptions
            do {
                try audioSession.setCategory(.playback, options: .duckOthers)
                try audioSession.setActive(true, options: [])
            } catch {
                activeUtteranceIDs.remove(utteranceID)
                // Activation did not take ownership. Put the category back where
                // this play attempt found it so a failed tap remains non-mixing
                // if the app had configured another category.
                try? audioSession.setCategory(priorCategory, options: priorCategoryOptions)
                return false
            }
        }

        speechEngine.speak(utterance)
        isSpeaking = true
        return true
    }

    /// Cancels all queued work when a pronunciation surface leaves the screen.
    /// AVSpeech delegate callbacks may arrive later; their accounting is idempotent.
    func cancel() {
        guard !activeUtteranceIDs.isEmpty else { return }

        activeUtteranceIDs.removeAll()
        isSpeaking = false
        _ = speechEngine.stopSpeaking(at: .immediate)
        deactivateAudioSession()
    }

    func pronunciationEngine(_ engine: any PronunciationSpeechEngine, didFinish utterance: AVSpeechUtterance) {
        retire(utterance)
    }

    func pronunciationEngine(_ engine: any PronunciationSpeechEngine, didCancel utterance: AVSpeechUtterance) {
        retire(utterance)
    }

    private func retire(_ utterance: AVSpeechUtterance) {
        let utteranceID = ObjectIdentifier(utterance)
        guard activeUtteranceIDs.contains(utteranceID) else { return }

        activeUtteranceIDs.remove(utteranceID)
        if activeUtteranceIDs.isEmpty {
            isSpeaking = false
            deactivateAudioSession()
        }
    }

    private func deactivateAudioSession() {
        do {
            try audioSession.setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            // Keeping the throw local avoids turning a callback into a crash.
            // Deactivation carries notifyOthers so interrupted apps are told to resume.
        }
    }
}
