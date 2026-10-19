import Foundation
import UniformTypeIdentifiers

enum ShareTextExtractor {
    /// Share providers can expose selection text through several legacy and
    /// modern type identifiers, so normalize the first usable item.
    static func extractText(from providers: [NSItemProvider]) async -> String? {
        for provider in providers {
            let preferredTypes = [
                UTType.plainText,
                UTType.utf8PlainText,
                UTType.text,
                UTType.url,
            ].compactMap(\.self)

            for type in preferredTypes where provider.hasItemConformingToTypeIdentifier(type.identifier) {
                if let text = await loadText(provider: provider, typeIdentifier: type.identifier) {
                    return normalized(text)
                }
            }
        }

        return nil
    }

    static func normalized(_ value: String) -> String? {
        let whitespace = CharacterSet.whitespacesAndNewlines
        let collapsed = value
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: whitespace)

        return collapsed.isEmpty ? nil : collapsed
    }

    private static func loadText(provider: NSItemProvider, typeIdentifier: String) async -> String? {
        let item: String? = await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: typeIdentifier, options: nil) { item, error in
                if error != nil {
                    continuation.resume(returning: nil)
                    return
                }

                switch item {
                case let text as String:
                    continuation.resume(returning: text)
                case let attributedText as NSAttributedString:
                    continuation.resume(returning: attributedText.string)
                case let url as URL:
                    continuation.resume(returning: url.absoluteString)
                case let url as NSURL:
                    continuation.resume(returning: url.absoluteString)
                case let data as Data:
                    continuation.resume(returning: String(data: data, encoding: .utf8))
                default:
                    continuation.resume(returning: nil)
                }
            }
        }

        return item
    }
}
