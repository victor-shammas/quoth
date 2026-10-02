import XCTest
@testable import QuothCore

/// Saving the dictionary from Settings and adding a word from Fix Last
/// Dictation, against a file in a temporary folder.
final class DictionaryEditingTests: XCTestCase {
    private var dir: URL!
    private var file: URL { dir.appendingPathComponent("dictionary") }

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    func testRowsRoundTrip() throws {
        let rows = [
            UserDictionary.Row(word: "PostHog", heardAs: ["post hog"]),
            UserDictionary.Row(word: "Parakeet", heardAs: []),
            UserDictionary.Row(word: "Kubernetes", heardAs: ["k8s", "kates"]),
        ]
        let dictionary = UserDictionary(rows: rows)
        XCTAssertEqual(dictionary.rows().rows, rows)
        XCTAssertEqual(try UserDictionary.parse(Data(dictionary.text().text.utf8)).rows().rows, rows)
    }

    func testBlankWordsAreDropped() {
        let dictionary = UserDictionary(rows: [.init(word: "  ", heardAs: ["x"]), .init(word: "Quoth", heardAs: [" ", "quote"])])
        XCTAssertEqual(dictionary.rows().rows, [.init(word: "Quoth", heardAs: ["quote"])])
    }

    func testSaveWritesAnOwnerOnlyFileAndAppliesAtOnce() throws {
        let store = DictionaryStore(file: file, log: { _ in })
        XCTAssertTrue(store.save(UserDictionary(rows: [.init(word: "PostHog", heardAs: ["post hog"])])))
        let mode = try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? Int
        XCTAssertEqual(mode, 0o600)
        XCTAssertEqual(store.current().replacer.apply(to: "the post hog dashboard"), "the PostHog dashboard")
    }

    func testSaveKeepsADotfilesSymlink() throws {
        let target = dir.appendingPathComponent("dotfiles-dictionary")
        try Data().write(to: target)
        try FileManager.default.createSymbolicLink(at: file, withDestinationURL: target)
        let store = DictionaryStore(file: file, log: { _ in })
        XCTAssertTrue(store.save(UserDictionary(rows: [.init(word: "Quoth", heardAs: [])])))
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: file.path), target.path)
        XCTAssertTrue(try String(contentsOf: target, encoding: .utf8).contains("Quoth"))
    }

    func testAddJoinsAnExistingRowInAnyCasing() throws {
        let store = DictionaryStore(file: file, log: { _ in })
        store.save(UserDictionary(rows: [.init(word: "Kubernetes", heardAs: ["k8s"]), .init(word: "Quoth", heardAs: [])]))
        XCTAssertTrue(store.add(word: "kubernetes", heardAs: "kates"))
        XCTAssertTrue(store.add(word: "Kubernetes", heardAs: "KATES"))
        XCTAssertTrue(store.add(word: "Gaugeline", heardAs: "gauge line"))
        XCTAssertEqual(store.current().dictionary.rows().rows, [
            // The latest spelling wins.
            .init(word: "Kubernetes", heardAs: ["k8s", "kates"]),
            .init(word: "Quoth", heardAs: []),
            .init(word: "Gaugeline", heardAs: ["gauge line"]),
        ])
        XCTAssertFalse(store.add(word: " ", heardAs: "x"))
    }

    func testSaveRefusesAFileWithAMistake() throws {
        let store = DictionaryStore(file: file, log: { _ in })
        store.save(UserDictionary(rows: [.init(word: "Quoth", heardAs: [])]))
        // A hand edit in progress: a comma in the word column.
        try "Word  Replaces\nPost, Hog  post hog\n".write(to: file, atomically: true, encoding: .utf8)
        XCTAssertFalse(store.save(UserDictionary(rows: [.init(word: "Other", heardAs: [])])))
        XCTAssertFalse(store.add(word: "Gaugeline", heardAs: "gauge line"))
        XCTAssertTrue(try String(contentsOf: file, encoding: .utf8).contains("Post, Hog"))
    }

    func testSaveRefusesAFileThatChangedSinceItWasRead() throws {
        let store = DictionaryStore(file: file, log: { _ in })
        store.save(UserDictionary(rows: [.init(word: "Quoth", heardAs: [])]))
        let base = store.current().dictionary
        // Fix Last Dictation adds a word while the editor holds `base`.
        XCTAssertTrue(store.add(word: "PostHog", heardAs: "post hog"))
        XCTAssertFalse(store.save(UserDictionary(rows: [.init(word: "Quoth", heardAs: ["quote"])]), basedOn: base))
        XCTAssertEqual(store.current().dictionary.rows().rows.map(\.word), ["Quoth", "PostHog"])
    }

    func testAddSplitsVariantsAndRefusesWordsTheFileCantHold() throws {
        let store = DictionaryStore(file: file, log: { _ in })
        XCTAssertFalse(store.add(word: "Smith, John", heardAs: "smith john"))
        XCTAssertFalse(store.add(word: "#tag", heardAs: "tag"))
        XCTAssertTrue(store.add(word: "Acme", heardAs: "ack me, akme"))
        XCTAssertEqual(store.current().dictionary.rows().rows, [.init(word: "Acme", heardAs: ["ack me", "akme"])])
    }
}

