import Testing
@testable import OpenLens

struct MarkdownContentViewTests {

    @MainActor
    @Test func longBlockquoteIsPreparedAsBoundedFragments() async {
        let quotedText = String(repeating: "quoted response fragment ", count: 500)
        let prepared = await prepareMarkdown("> \(quotedText)")

        guard case let .blockquote(fragments) = prepared.blocks.first?.kind else {
            Issue.record("Expected a blockquote")
            return
        }

        #expect(fragments.count > 1)
        #expect(fragments.allSatisfy { $0.raw.count <= 1_600 })
    }

    @MainActor
    @Test func longListItemUsesBoundedContinuationFragments() async {
        let longItem = String(repeating: "long list item fragment ", count: 500)
        let prepared = await prepareMarkdown("- \(longItem)\n- final item")

        guard case let .unorderedList(fragments) = prepared.blocks.first?.kind else {
            Issue.record("Expected an unordered list")
            return
        }

        #expect(fragments.count > 2)
        #expect(fragments.allSatisfy { $0.raw.count <= 1_600 })
        #expect(fragments.first?.marker == "•")
        #expect(fragments.dropFirst().contains { $0.marker == nil })
        #expect(fragments.last?.marker == "•")
    }

    @MainActor
    @Test func longHeadingIsPreparedAsBoundedBlocks() async {
        let heading = "# " + String(repeating: "heading fragment ", count: 500)
        let prepared = await prepareMarkdown(heading)
        let headingTexts = prepared.blocks.compactMap { block -> String? in
            guard case let .heading(_, text) = block.kind else { return nil }
            return text
        }

        #expect(headingTexts.count > 1)
        #expect(headingTexts.allSatisfy { $0.count <= 1_600 })
    }

    @MainActor
    @Test func fencedCodeLanguageLabelIsBounded() async {
        let language = String(repeating: "swift", count: 100)
        let prepared = await prepareMarkdown("```\(language)\nlet answer = 42\n```")

        guard case let .codeBlock(label, _) = prepared.blocks.first?.kind else {
            Issue.record("Expected a code block")
            return
        }

        #expect(label?.count == 83)
        #expect(label?.hasSuffix("...") == true)
    }

    @MainActor
    @Test func simpleTableIsParsed() async {
        let markdown = """
        | Name | Age |
        |------|-----|
        | Alice | 30 |
        | Bob | 25 |
        """
        let prepared = await prepareMarkdown(markdown)

        guard case let .table(data) = prepared.blocks.first?.kind else {
            Issue.record("Expected a table")
            return
        }

        #expect(data.headers.map(\.raw) == ["Name", "Age"])
        #expect(data.columnCount == 2)
        #expect(data.rows.count == 2)
        #expect(data.rows[0].map(\.raw) == ["Alice", "30"])
        #expect(data.rows[1].map(\.raw) == ["Bob", "25"])
        #expect(data.alignments.count == 2)
    }

    @MainActor
    @Test func tableAlignmentsAreParsed() async {
        let markdown = """
        | Left | Center | Right |
        |:-----|:------:|------:|
        | a | b | c |
        """
        let prepared = await prepareMarkdown(markdown)

        guard case let .table(data) = prepared.blocks.first?.kind else {
            Issue.record("Expected a table")
            return
        }

        #expect(data.alignments.count == 3)
        #expect(data.alignments[0] == .left)
        #expect(data.alignments[1] == .center)
        #expect(data.alignments[2] == .right)
    }

    @MainActor
    @Test func tableWithoutLeadingPipesIsParsed() async {
        let markdown = """
        Name | Age
        ---- | ---
        Alice | 30
        """
        let prepared = await prepareMarkdown(markdown)

        guard case let .table(data) = prepared.blocks.first?.kind else {
            Issue.record("Expected a table")
            return
        }

        #expect(data.headers.map(\.raw) == ["Name", "Age"])
        #expect(data.rows.count == 1)
    }

    @MainActor
    @Test func pipeInParagraphIsNotTable() async {
        let markdown = "This is a line with a | pipe but no separator"
        let prepared = await prepareMarkdown(markdown)

        guard case .paragraph = prepared.blocks.first?.kind else {
            Issue.record("Expected a paragraph, not a table")
            return
        }
    }

    @MainActor
    @Test func escapedPipesArePreservedInTableCells() async {
        let markdown = """
        | Expression | Result |
        |------------|--------|
        | a \\| b | pipe |
        """
        let prepared = await prepareMarkdown(markdown)

        guard case let .table(data) = prepared.blocks.first?.kind else {
            Issue.record("Expected a table")
            return
        }

        #expect(data.rows[0][0].raw == "a | b")
        #expect(data.rows[0][1].raw == "pipe")
    }

    @MainActor
    @Test func tableCellsContainInlineMarkdownAttributedStrings() async {
        let markdown = """
        | Header |
        |--------|
        | **bold** and *italic* |
        """
        let prepared = await prepareMarkdown(markdown)

        guard case let .table(data) = prepared.blocks.first?.kind else {
            Issue.record("Expected a table")
            return
        }

        // Header has no inline markdown markers, so attributed may be nil.
        // But the data cell contains bold/italic, so attributed should be non-nil.
        #expect(data.rows[0][0].attributed != nil)
    }

    @MainActor
    @Test func shortTableRowIsPaddedToHeaderColumnCount() async {
        let markdown = """
        | A | B | C |
        |---|---|---|
        | 1 |
        """
        let prepared = await prepareMarkdown(markdown)

        guard case let .table(data) = prepared.blocks.first?.kind else {
            Issue.record("Expected a table")
            return
        }

        #expect(data.columnCount == 3)
        #expect(data.rows[0].count == 3)
        #expect(data.rows[0][0].raw == "1")
        #expect(data.rows[0][1].raw == "")
        #expect(data.rows[0][2].raw == "")
    }

    @MainActor
    @Test func excessColumnsAreTruncatedToHeaderCount() async {
        let markdown = """
        | A | B |
        |---|---|
        | 1 | 2 | 3 | 4 |
        """
        let prepared = await prepareMarkdown(markdown)

        guard case let .table(data) = prepared.blocks.first?.kind else {
            Issue.record("Expected a table")
            return
        }

        #expect(data.columnCount == 2)
        #expect(data.rows[0].count == 2)
        #expect(data.rows[0][0].raw == "1")
        #expect(data.rows[0][1].raw == "2")
    }

    @MainActor
    @Test func emptyTableCellsAreParsed() async {
        let markdown = """
        | A | B |
        |---|---|
        |   |   |
        """
        let prepared = await prepareMarkdown(markdown)

        guard case let .table(data) = prepared.blocks.first?.kind else {
            Issue.record("Expected a table")
            return
        }

        #expect(data.rows[0][0].raw == "")
        #expect(data.rows[0][1].raw == "")
    }

    @MainActor
    @Test func longTableCellContentIsPreservedInFull() async {
        let longContent = String(repeating: "x", count: 1000)
        let markdown = """
        | Header |
        |--------|
        | \(longContent) |
        """
        let prepared = await prepareMarkdown(markdown)

        guard case let .table(data) = prepared.blocks.first?.kind else {
            Issue.record("Expected a table")
            return
        }

        // Cell content is preserved in full — no truncation
        #expect(data.rows[0][0].raw.count == 1000)
        #expect(data.rows[0][0].raw == longContent)
    }

    @MainActor
    @Test func escapedBackslashBeforePipeIsHandled() async {
        // In Swift: "\\\\" = two backslashes in the actual string
        // The parser sees: backslash, backslash, pipe
        // It treats \| as escaped pipe, but \\ is not handled as escaped backslash
        // So: first \ looks at next char (\), not |, keeps both \\
        // Then | is treated as separator
        // Result: cell1 = "a \\" (two backslashes), cell2 = "b"
        let markdown = "| A | B |\n|---|---|\n| a \\\\| b | c |"
        let prepared = await prepareMarkdown(markdown)

        guard case let .table(data) = prepared.blocks.first?.kind else {
            Issue.record("Expected a table")
            return
        }

        #expect(data.columnCount == 2)
        // First cell contains "a " followed by two backslashes
        #expect(data.rows[0][0].raw == "a \\\\")
        #expect(data.rows[0][1].raw == "b")
    }

    @MainActor
    private func prepareMarkdown(_ text: String) async -> MarkdownContentView.Prepared {
        await withCheckedContinuation { continuation in
            MarkdownContentView.prepare(text) { prepared in
                continuation.resume(returning: prepared)
            }
        }
    }
}
