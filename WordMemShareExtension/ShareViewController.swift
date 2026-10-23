import SwiftUI
import Translation
import UIKit

final class ShareViewController: UIViewController {
    private let storageManager = LocalStorageManager()

    override func viewDidLoad() {
        super.viewDidLoad()

        let providers = (extensionContext?.inputItems.compactMap { $0 as? NSExtensionItem } ?? [])
            .flatMap { $0.attachments ?? [] }
        let card = ShareCardView(
            storageManager: storageManager,
            sharedItemProviders: providers,
            onClose: { [weak self] in
                self?.closeExtension()
            }
        )
        let hostingController = UIHostingController(rootView: card)
        addChild(hostingController)
        view.addSubview(hostingController.view)
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            hostingController.view.topAnchor.constraint(equalTo: view.topAnchor),
            hostingController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        hostingController.didMove(toParent: self)
    }

    private func closeExtension() {
        guard let url = URL(string: "wordmem://saved") else {
            extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
            return
        }

        extensionContext?.open(url) { [weak extensionContext] _ in
            extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
        }
    }
}

private struct ShareCardView: View {
    @ObservedObject var storageManager: LocalStorageManager
    let sharedItemProviders: [NSItemProvider]
    let onClose: () -> Void

    @State private var configuration: TranslationSession.Configuration?
    @State private var pendingText = ""
    @State private var sourceText = ""
    @State private var translatedText = ""
    @State private var noteText = ""
    @State private var wordText = ""
    @State private var advisedChip: ImportCandidateChip?
    @State private var advisorToken = UUID()
    @State private var phoneticText = ""
    @State private var exampleText = ""
    @State private var showAdvancedFields = false
    @State private var status: Status = .extracting
    @State private var persistenceError: String?

    enum Status: Equatable {
        case extracting
        case translating
        case ready
        case translationFailed
        case unsupported
        case saved
    }

    private var canSave: Bool {
        let word = wordText.trimmingCharacters(in: .whitespacesAndNewlines)
        let meaning = translatedText.trimmingCharacters(in: .whitespacesAndNewlines)
        return status != .extracting && status != .translating && status != .saved
            && !word.isEmpty && !meaning.isEmpty
            && (advisedChip?.isImportable == true)
    }

    var body: some View {
        NavigationView {
            Form {
                if let persistenceError {
                    Section {
                        Label(persistenceError, systemImage: "externaldrive.badge.exclamationmark")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    }
                }

                Section("原文") {
                    Text(sourceText.isEmpty ? "正在获取分享内容…" : sourceText)
                        .font(.body)
                        .foregroundStyle(sourceText.isEmpty ? Color.secondary : Color.primary)
                        .textSelection(.enabled)
                }

                Section("中文释义") {
                    if status == .translating {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text("正在翻译…")
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        TextEditor(text: $translatedText)
                            .frame(minHeight: 76)
                            .accessibilityLabel("编辑中文释义")

                        Button("重新翻译") {
                            startTranslation()
                        }
                        .disabled(sourceText.isEmpty)
                    }

                    if status == .translationFailed {
                        Label("翻译不可用，请手动输入释义。", systemImage: "exclamationmark.triangle")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    }
                }

                Section("记忆笔记") {
                    TextEditor(text: $noteText)
                        .frame(minHeight: 76)
                        .accessibilityLabel("添加记忆笔记")
                }

                Section {
                    DisclosureGroup("编辑单词详情", isExpanded: $showAdvancedFields) {
                        TextField("单词", text: $wordText)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .onChange(of: wordText, initial: true) {
                                refreshAdvice()
                            }
                        TextField("音标", text: $phoneticText)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        TextField("例句", text: $exampleText)
                    }
                }

                if let chip = advisedChip {
                    Section("系统词典检查") {
                        HStack(spacing: 8) {
                            if let lemmaText = chip.lemmaBadgeText {
                                Text(lemmaText)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.indigo)
                            }
                            if let spellingText = chip.spellingBadgeText {
                                Text(spellingText)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.orange)
                            }
                            if let unavailableText = chip.availabilityBadgeText {
                                Text(unavailableText)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.red)
                            }
                            if chip.isImportable && chip.advice?.isOriginalRestored != true {
                                Label("可导入", systemImage: "checkmark.circle.fill")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.green)
                            }
                            Spacer()
                            if !chip.isImportable {
                                Button("还原原拼写") {
                                    advisedChip = chip.restoringOriginal()
                                }
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.orange)
                            }
                        }
                    }
                }

                Section {
                    if status == .unsupported {
                        ContentUnavailableView(
                            "没有可用文本",
                            systemImage: "text.badge.xmark",
                            description: Text("请分享选中的英文文本后重试。")
                        )
                    } else if status == .saved {
                        Label("已保存到 WordMem", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                }
            }
            .navigationTitle("WordMem")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭", action: onClose)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存", action: save)
                        .fontWeight(.semibold)
                        .disabled(!canSave)
                }
            }
            .onAppear(perform: loadSharedText)
            .translationTask(configuration) { session in
                await translate(with: session)
            }
        }
        .navigationViewStyle(.stack)
    }

    private func loadSharedText() {
        guard status == .extracting, sourceText.isEmpty else { return }
        let providers = sharedItemProviders

        Task { @MainActor in
            let extracted = await ShareTextExtractor.extractText(from: providers)
            guard let extracted else {
                sourceText = ""
                status = .unsupported
                return
            }

            sourceText = extracted
            wordText = extracted
            pendingText = extracted
            startTranslation()
        }
    }

    private func startTranslation() {
        guard !pendingText.isEmpty else {
            status = sourceText.isEmpty ? .unsupported : .translationFailed
            return
        }

        status = .translating
        configuration = TranslationSession.Configuration(
            source: Locale.Language(identifier: "en"),
            target: Locale.Language(identifier: "zh-Hans")
        )
    }

    private func translate(with session: TranslationSession) async {
        guard status == .translating else { return }
        do {
            let response = try await session.translate(pendingText)
            translatedText = response.targetText
            status = .ready
            configuration = nil
        } catch {
            status = .translationFailed
            configuration = nil
        }
    }

    private func refreshAdvice() {
        let token = UUID()
        advisorToken = token
        let rawWord = wordText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawWord.isEmpty else {
            advisedChip = nil
            return
        }

        Task {
            let candidate = WordImportCandidate(
                text: rawWord,
                normalizedKey: WordInputNormalizer.normalizedKey(from: rawWord)
            )
            let chip = await ImportWordAdvisor.live().chips(
                from: [candidate],
                context: sourceText.isEmpty ? nil : sourceText
            ).first
            guard advisorToken == token else { return }
            advisedChip = chip
        }
    }

    private func save() {
        guard let selectedChip = advisedChip, selectedChip.isImportable else { return }
        let normalizedMeaning = translatedText.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedNote = noteText.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedPhonetic = phoneticText.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedExample = exampleText.trimmingCharacters(in: .whitespacesAndNewlines)

        var candidate = ImportCandidatePipeline.payload(from: selectedChip)
        candidate.userTranslation = normalizedMeaning
        candidate.userPhonetic = normalizedPhonetic.isEmpty ? nil : normalizedPhonetic
        candidate.userExample = normalizedExample.isEmpty ? nil : normalizedExample
        candidate.userNote = normalizedNote.isEmpty ? nil : normalizedNote

        let submission = WordImportSubmission(
            source: .shareExtension,
            sourceText: sourceText,
            recognizedText: sourceText,
            candidates: [candidate],
            metadata: ["channel": "share_extension"]
        )
        let error = WordImportExtensionSaveService.saveShare(
            submission,
            storage: storageManager,
            onSaved: {
                status = .saved
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                    onClose()
                }
            }
        )
        persistenceError = error
    }
}
