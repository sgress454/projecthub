import Foundation
import XCTest
@testable import ProjectHubKit

final class ClassifierOutputParsingTests: XCTestCase {
    func testExactQuestion() {
        XCTAssertEqual(Classifier.parseClassifierOutput("QUESTION"), .question)
    }

    func testExactReport() {
        XCTAssertEqual(Classifier.parseClassifierOutput("REPORT"), .report)
    }

    func testExactDone() {
        XCTAssertEqual(Classifier.parseClassifierOutput("DONE"), .done)
    }

    func testWhitespaceAndNewlineTolerant() {
        XCTAssertEqual(Classifier.parseClassifierOutput("  DONE  \n"), .done)
        XCTAssertEqual(Classifier.parseClassifierOutput("\nQUESTION\n"), .question)
    }

    func testCaseInsensitive() {
        XCTAssertEqual(Classifier.parseClassifierOutput("question"), .question)
        XCTAssertEqual(Classifier.parseClassifierOutput("Done"), .done)
    }

    func testTolerantOfPunctuation() {
        XCTAssertEqual(Classifier.parseClassifierOutput("REPORT."), .report)
        XCTAssertEqual(Classifier.parseClassifierOutput("-> DONE"), .done)
    }

    func testUnrecognizedReturnsFailure() {
        XCTAssertEqual(Classifier.parseClassifierOutput(""), .failure)
        XCTAssertEqual(Classifier.parseClassifierOutput("MAYBE"), .failure)
        XCTAssertEqual(Classifier.parseClassifierOutput("I don't know"), .failure)
    }

    func testStripsAnsi() {
        let ansi = "\u{001B}[32mQUESTION\u{001B}[0m"
        XCTAssertEqual(Classifier.parseClassifierOutput(ansi), .question)
    }
}

final class TranscriptReaderTests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ProjectHubTranscript-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempDir { try? FileManager.default.removeItem(at: tempDir) }
    }

    func testExtractsTextFromBlocksInLastAssistantLine() throws {
        let url = tempDir.appendingPathComponent("t.jsonl")
        let lines = [
            #"{"type":"user","message":{"role":"user","content":"hi"}}"#,
            #"{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"first"}]}}"#,
            #"{"type":"user","message":{"role":"user","content":"go"}}"#,
            #"{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"second"},{"type":"tool_use","name":"x"}]}}"#,
        ]
        try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)

        let text = TranscriptReader.finalAssistantText(fromTranscriptAt: url)
        XCTAssertEqual(text, "second")
    }

    func testHandlesStringContentShape() throws {
        let url = tempDir.appendingPathComponent("t.jsonl")
        let line = #"{"type":"assistant","message":{"role":"assistant","content":"done"}}"#
        try line.write(to: url, atomically: true, encoding: .utf8)
        XCTAssertEqual(TranscriptReader.finalAssistantText(fromTranscriptAt: url), "done")
    }

    func testSkipsToolOnlyMessages() throws {
        let url = tempDir.appendingPathComponent("t.jsonl")
        let lines = [
            #"{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"real"}]}}"#,
            #"{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","name":"x"}]}}"#,
        ]
        try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
        // Last line has no text blocks → extractText returns nil → keep walking.
        // Confirm we fall back to the earlier assistant text.
        XCTAssertEqual(TranscriptReader.finalAssistantText(fromTranscriptAt: url), "real")
    }

    func testMissingFileReturnsNil() {
        let url = tempDir.appendingPathComponent("no.jsonl")
        XCTAssertNil(TranscriptReader.finalAssistantText(fromTranscriptAt: url))
    }

    func testNoAssistantMessageReturnsNil() throws {
        let url = tempDir.appendingPathComponent("t.jsonl")
        let line = #"{"type":"user","message":{"role":"user","content":"just user"}}"#
        try line.write(to: url, atomically: true, encoding: .utf8)
        XCTAssertNil(TranscriptReader.finalAssistantText(fromTranscriptAt: url))
    }
}

final class ClassifierResolutionTests: XCTestCase {
    func testMissingClaudeCLIReturnsFailureForMessageClassify() async {
        let classifier = Classifier()
        // Override with a nonexistent path
        await classifier.overrideClaudePath("/nonexistent/claude")
        let result = await classifier.classify(message: "done.")
        // Process.run() on a nonexistent path throws → runProcess returns nil
        // → classify returns .failure.
        XCTAssertEqual(result, .failure)
    }

    func testNilPathOverrideMeansNoClaudeAvailable() async {
        let classifier = Classifier()
        await classifier.overrideClaudePath(nil)
        let result = await classifier.classify(message: "done.")
        XCTAssertEqual(result, .failure)
    }
}
