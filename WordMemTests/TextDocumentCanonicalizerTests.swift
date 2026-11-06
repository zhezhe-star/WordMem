import Foundation
import XCTest

@testable import WordMem

final class TextDocumentCanonicalizerTests: XCTestCase {
    private let canonicalizer = TextDocumentCanonicalizer()

    func testParagraphsSplitOnBlankLinesAndKeepUTF16SpanRange() throws {
        let document = canonicalizer.canonicalize(
            """
            First paragraph line one
            First paragraph line two

            Second paragraph
            """,
            origin: .pastedText
        )

        XCTAssertEqual(document.blocks.map(\.kind), [.paragraph, .paragraph])
        XCTAssertEqual(document.blocks.map(\.text), [
            "First paragraph line one\nFirst paragraph line two",
            "Second paragraph",
        ])

        let firstSpan = try XCTUnwrap(document.blocks[0].spans.first)
        XCTAssertEqual(firstSpan.text, document.blocks[0].text)
        XCTAssertEqual(firstSpan.charRange.lowerBound, 0)
        XCTAssertEqual(firstSpan.charRange.upperBound, firstSpan.text.utf16.count)
    }

    func testDetectsHeadingsListItemsQuotesAndFencedCode() throws {
        let document = canonicalizer.canonicalize(
            """
            # Release notes

            - Add document pipeline
            * Improve import flow
            1. Ship canonical models

            > Local-first content

            ```swift
            let value = 1
              preserve indentation
            ```
            """,
            origin: .typedText
        )

        XCTAssertEqual(document.blocks.map(\.kind), [
            .heading, .listItem, .listItem, .listItem, .quote, .code,
        ])
        XCTAssertEqual(document.blocks.map(\.text), [
            "Release notes",
            "Add document pipeline",
            "Improve import flow",
            "Ship canonical models",
            "Local-first content",
            "let value = 1\n  preserve indentation",
        ])
    }

    func testCanonicalizationUsesDeterministicAndUniqueIdentifiers() throws {
        let text = "Repeated\n\nRepeated\n\nRepeated"
        let first = canonicalizer.canonicalize(text, origin: .typedText)
        let second = canonicalizer.canonicalize(text, origin: .typedText)

        XCTAssertEqual(first, second)
        XCTAssertEqual(first.blocks.count, 3)

        let allIDs = first.blocks.flatMap { block in
            [block.id] + block.spans.map(\.id)
        }
        XCTAssertEqual(allIDs.count, Set(allIDs).count)
        XCTAssertEqual(first.blocks.map(\.order), [0, 1, 2])
    }

    func testEmptyAndWhitespaceOnlyInputProducesValidEmptyDocument() throws {
        XCTAssertEqual(
            canonicalizer.canonicalize("", origin: .typedText).blocks,
            []
        )
        XCTAssertEqual(
            canonicalizer.canonicalize(" \n\t \n\r\n  ", origin: .pastedText).blocks,
            []
        )
    }
}
