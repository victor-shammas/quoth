import WhisperKit
import XCTest
@testable import QuothCore
@testable import QuothDomain
@testable import QuothPlatform
@testable import QuothSpeech

final class LivePromptTests: XCTestCase {
    func testThePromptContinuesThePreviousSegment() {
        XCTAssertEqual(WhisperKitTranscriber.prompt("Quoth and WhisperKit.", continuing: nil), "Quoth and WhisperKit.")
        XCTAssertEqual(WhisperKitTranscriber.prompt(nil, continuing: "I went to the"), "I went to the")
        XCTAssertEqual(WhisperKitTranscriber.prompt("Quoth.", continuing: "I went to the"), "Quoth. I went to the")
        let long = String(repeating: "word ", count: 100)
        XCTAssertEqual(WhisperKitTranscriber.prompt(nil, continuing: long)?.count, 200)
    }
}

final class DictionaryContextTests: XCTestCase {
    // MARK: Context

    func testContextGivesThePromptOnlyForAKnownMatchingLanguage() throws {
        let dir = try TemporaryDirectory()
        let file = dir.url.appendingPathComponent("dictionary")
        try "PostHog  post hog\n".write(to: file, atomically: true, encoding: .utf8)
        let store = DictionaryStore(file: file, log: { _ in })
        // From settings.json, not the dictionary file.
        let examples = ["en": "I opened PostHog."]

        let english = DictionaryContext(store: store, language: "en", examples: examples).context()
        XCTAssertEqual(english, TranscriptionContext(language: "en", prompt: "I opened PostHog.", vocabulary: ["PostHog"]))

        // Automatic: no prompt yet; the examples go along for the engine to pick from.
        let unknown = DictionaryContext(store: store, language: nil, examples: examples).context()
        XCTAssertNil(unknown.prompt)
        XCTAssertNil(unknown.language)
        XCTAssertEqual(unknown.examples, ["en": "I opened PostHog."])

        XCTAssertNil(DictionaryContext(store: store, language: "pt", examples: examples).context().prompt)
        XCTAssertNil(DictionaryContext(store: store, language: "en").context().prompt, "no examples, no prompt")
    }

    func testSavedExamplesReadTheSettingsFile() throws {
        let dir = try TemporaryDirectory()
        let file = dir.url.appendingPathComponent("settings.json")
        XCTAssertEqual(DictionaryContext.savedExamples(in: file), [:], "missing file")
        try #"{"dictionary": {"examples": {"en": "I opened PostHog."}}, "hotkey": {"key": "fn"}}"#
            .write(to: file, atomically: true, encoding: .utf8)
        XCTAssertEqual(DictionaryContext.savedExamples(in: file), ["en": "I opened PostHog."])
        try "{".write(to: file, atomically: true, encoding: .utf8)
        XCTAssertEqual(DictionaryContext.savedExamples(in: file), [:], "unparseable file")
    }

    func testKnownLanguageOnlyForSingleLanguageModels() throws {
        let base = try XCTUnwrap(ModelRegistry.find("whisper-base.en"))
        let turbo = try XCTUnwrap(ModelRegistry.find("whisper-large-v3-turbo"))
        XCTAssertEqual(base.onlyLanguage, "en")
        XCTAssertNil(turbo.onlyLanguage)
    }

    func testLanguageFollowsTheSettingOnlyForMultilingualModels() throws {
        let base = try XCTUnwrap(ModelRegistry.find("whisper-base.en"))
        let turbo = try XCTUnwrap(ModelRegistry.find("whisper-large-v3-turbo"))
        XCTAssertEqual(DictionaryContext.language(of: base, setting: "pt"), "en")
        XCTAssertEqual(DictionaryContext.language(of: turbo, setting: "pt"), "pt")
        XCTAssertNil(DictionaryContext.language(of: turbo, setting: nil))
        XCTAssertNil(DictionaryContext.language(of: turbo, setting: "xx"))
    }

    /// In Automatic the transcriber picks the example for the language it
    /// settled on, and never one in another language.
    func testDetectedLanguagePicksItsOwnExample() {
        let examples = ["en": "I opened PostHog.", "pt-BR": "Abri o PostHog."]
        XCTAssertEqual(WhisperKitTranscriber.example(in: examples, for: "pt"), "Abri o PostHog.")
        XCTAssertEqual(WhisperKitTranscriber.example(in: examples, for: "en"), "I opened PostHog.")
        XCTAssertNil(WhisperKitTranscriber.example(in: examples, for: "es"))
        XCTAssertNil(WhisperKitTranscriber.example(in: examples, for: nil))
        XCTAssertNil(WhisperKitTranscriber.example(in: [:], for: "en"))
    }

    // MARK: Whisper prompt tokens

    /// Encodes each character as its scalar value, prefixed with a special
    /// token; a "<" also becomes a special token.
    private struct FakeTokenizer: WhisperTokenizer {
        static let specialBegin = 50_000

        func encode(text: String) -> [Int] {
            [Self.specialBegin + 7] + text.unicodeScalars.map { $0 == "<" ? Self.specialBegin + 1 : Int($0.value) }
        }

        func decode(tokens: [Int]) -> String { "" }
        func convertTokenToId(_ token: String) -> Int? { nil }
        func convertIdToToken(_ id: Int) -> String? { nil }
        var allLanguageTokens: Set<Int> { [] }
        func splitToWordTokens(tokenIds: [Int]) -> (words: [String], wordTokens: [[Int]]) { ([], []) }

        var specialTokens: SpecialTokens {
            SpecialTokens(
                endToken: Self.specialBegin, englishToken: Self.specialBegin + 2, noSpeechToken: Self.specialBegin + 3,
                noTimestampsToken: Self.specialBegin + 4, specialTokenBegin: Self.specialBegin,
                startOfPreviousToken: Self.specialBegin + 5, startOfTranscriptToken: Self.specialBegin + 6,
                timeTokenBegin: Self.specialBegin + 100, transcribeToken: Self.specialBegin + 8,
                translateToken: Self.specialBegin + 9, whitespaceToken: 32
            )
        }
    }

    func testPromptTokensDropSpecialTokensAndLeadWithASpace() {
        let tokens = WhisperKitTranscriber.promptTokens(for: " a<b ", tokenizer: FakeTokenizer())
        XCTAssertEqual(tokens, [32, 97, 98])
    }

    func testNoPromptTokensWithoutAPrompt() {
        XCTAssertNil(WhisperKitTranscriber.promptTokens(for: nil, tokenizer: FakeTokenizer()))
        XCTAssertNil(WhisperKitTranscriber.promptTokens(for: "  \n", tokenizer: FakeTokenizer()))
        XCTAssertNil(WhisperKitTranscriber.promptTokens(for: "text", tokenizer: nil))
    }
}
