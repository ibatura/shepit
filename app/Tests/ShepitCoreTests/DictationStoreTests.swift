import Foundation
import SQLite3
import Testing
@testable import ShepitCore

// Dictations and Dictionary design §4.
struct DictationStoreTests {
    private func store() -> (DictationStore, URL) {
        let dir = FileManager.default.temporaryDirectory.appending(path: "dictation-store-\(UUID().uuidString)")
        return (DictationStore(file: dir.appending(path: "dictations.sqlite")), dir)
    }

    private let start = Date(timeIntervalSince1970: 1_785_484_800)
    private let slack = AppRef(bundleID: "com.tinyspeck.slackmacgap", name: "Slack")

    @Test func entriesComeBackNewestFirstAndSurviveReopening() throws {
        let (store, dir) = store()
        defer { try? FileManager.default.removeItem(at: dir) }
        let first = try store.add(text: "Окей, давай після обіду.", app: slack, at: start)
        let second = try store.add(text: "  The build is\tgreen again. ", app: nil, at: start.addingTimeInterval(60))
        let expected = [
            DictationStore.Entry(id: second, time: start.addingTimeInterval(60), appName: nil, appBundleID: nil,
                                 text: "  The build is\tgreen again. ", words: 5),
            DictationStore.Entry(id: first, time: start, appName: "Slack", appBundleID: "com.tinyspeck.slackmacgap",
                                 text: "Окей, давай після обіду.", words: 4),
        ]
        #expect(try store.page(limit: 10) == expected)
        #expect(try store.page(limit: 1) == [expected[0]])
        #expect(try DictationStore(file: store.file).page(limit: 10) == expected)
        #expect(try version(store.file) == 1)
    }

    @Test func pagesContinueWithoutRepeatsOrGapsWithinOneSecond() throws {
        let (store, dir) = store()
        defer { try? FileManager.default.removeItem(at: dir) }
        var ids: [Int] = []
        for i in 0..<7 { ids.append(try store.add(text: "entry \(i)", app: nil, at: start.addingTimeInterval(i < 5 ? 0 : Double(i)))) }
        var seen: [Int] = []
        var last: DictationStore.Entry?
        while true {
            let page = try store.page(before: last, limit: 2)
            guard let end = page.last else { break }
            seen += page.map(\.id)
            last = end
        }
        #expect(seen == [ids[6], ids[5], ids[4], ids[3], ids[2], ids[1], ids[0]])
    }

    @Test func pagesStopAtThePeriodsStart() throws {
        let (store, dir) = store()
        defer { try? FileManager.default.removeItem(at: dir) }
        for i in 0..<5 { try store.add(text: "entry \(i)", app: nil, at: start.addingTimeInterval(Double(i) * 60)) }
        let since = start.addingTimeInterval(120)
        let first = try store.page(since: since, limit: 2)
        #expect(first.map(\.text) == ["entry 4", "entry 3"])
        #expect(try store.page(before: first.last, since: since, limit: 2).map(\.text) == ["entry 2"])
    }

    @Test func deleteRemovesOneEntry() throws {
        let (store, dir) = store()
        defer { try? FileManager.default.removeItem(at: dir) }
        let keep = try store.add(text: "keep", app: nil, at: start)
        let drop = try store.add(text: "drop", app: nil, at: start.addingTimeInterval(1))
        try store.delete(drop)
        #expect(try store.page(limit: 10).map(\.id) == [keep])
    }

    @Test func pruneRemovesOlderEntriesAndCountsThem() throws {
        let (store, dir) = store()
        defer { try? FileManager.default.removeItem(at: dir) }
        try store.add(text: "old", app: nil, at: start)
        try store.add(text: "older", app: nil, at: start.addingTimeInterval(-10))
        let new = try store.add(text: "new", app: nil, at: start.addingTimeInterval(10))
        #expect(try store.prune(before: start.addingTimeInterval(1)) == 2)
        #expect(try store.page(limit: 10).map(\.id) == [new])
        #expect(try store.prune(before: start) == 0)
    }

    @Test func clearDeletesTheFileAndTheNextAddStartsANewOne() throws {
        let (store, dir) = store()
        defer { try? FileManager.default.removeItem(at: dir) }
        try store.add(text: "secret", app: nil, at: start)
        try store.clear()
        #expect(!FileManager.default.fileExists(atPath: store.file.path))
        try store.add(text: "again", app: nil, at: start)
        #expect(try store.page(limit: 10).map(\.text) == ["again"])
    }

    @Test func readingCreatesNoFile() throws {
        let (store, dir) = store()
        defer { try? FileManager.default.removeItem(at: dir) }
        #expect(try store.page(limit: 10).isEmpty)
        #expect(try store.prune(before: start) == 0)
        try store.delete(1)
        #expect(!FileManager.default.fileExists(atPath: store.file.path))
    }

    @Test func aFileDeletedUnderTheStoreIsCreatedAgain() throws {
        let (store, dir) = store()
        defer { try? FileManager.default.removeItem(at: dir) }
        try store.add(text: "gone", app: nil, at: start)
        try FileManager.default.removeItem(at: store.file)
        #expect(try store.page(limit: 10).isEmpty)
        try store.add(text: "again", app: nil, at: start)
        #expect(FileManager.default.fileExists(atPath: store.file.path))
        #expect(try DictationStore(file: store.file).page(limit: 10).map(\.text) == ["again"])
    }

    /// Long texts end on overflow pages, which macOS's default `secure_delete = FAST` leaves as they were.
    @Test func deletedAndPrunedTextLeavesNoTraceInTheFile() throws {
        let (store, dir) = store()
        defer { try? FileManager.default.removeItem(at: dir) }
        let long = String(repeating: "word ", count: 3000)
        try store.add(text: "kept words", app: nil, at: start.addingTimeInterval(100))
        let deleted = try store.add(text: long + "Marker-deleted-7Q2X", app: nil, at: start.addingTimeInterval(50))
        try store.add(text: long + "Marker-pruned-9K4Z", app: nil, at: start)
        try store.delete(deleted)
        try store.prune(before: start.addingTimeInterval(1))
        let bytes = try Data(contentsOf: store.file)
        #expect(bytes.range(of: Data("kept words".utf8)) != nil)
        #expect(bytes.range(of: Data("Marker-deleted-7Q2X".utf8)) == nil)
        #expect(bytes.range(of: Data("Marker-pruned-9K4Z".utf8)) == nil)
    }

    private func version(_ file: URL) throws -> Int32 {
        var handle: OpaquePointer?
        guard sqlite3_open(file.path, &handle) == SQLITE_OK else { throw CocoaError(.fileReadUnknown) }
        defer { sqlite3_close(handle) }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, "SELECT version FROM schema_version", -1, &statement, nil) == SQLITE_OK else {
            throw CocoaError(.fileReadUnknown)
        }
        defer { sqlite3_finalize(statement) }
        return sqlite3_step(statement) == SQLITE_ROW ? sqlite3_column_int(statement, 0) : 0
    }

    @Test func everyChangeIsReported() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "dictations-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        var reported = 0
        let store = DictationStore(file: dir.appending(path: "dictations.sqlite")) { reported += 1 }
        let id = try store.add(text: "one", app: nil, at: Date(timeIntervalSince1970: 100))
        try store.add(text: "two", app: nil, at: Date(timeIntervalSince1970: 200))
        try store.delete(id)
        try store.prune(before: Date(timeIntervalSince1970: 150)) // nothing that old: no report
        try store.prune(before: Date(timeIntervalSince1970: 250))
        _ = try store.page(limit: 10)
        try store.clear()
        #expect(reported == 5)
    }
}
