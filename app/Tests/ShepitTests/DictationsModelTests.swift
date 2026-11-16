import Foundation
import Testing
@testable import Shepit
import ShepitCore

// Dictations and Dictionary design §5: pages, open rows and Delete in the Dictations section. The store itself is tested in
// DictationStoreTests, the day groups and row texts in DictationPageTests.
@MainActor
struct DictationsModelTests {
    private let start = Date(timeIntervalSince1970: 1_785_484_800)

    /// A store with `count` entries a minute apart, "entry 0" the oldest; the section shows all history. As in the app,
    /// a change of the store reloads the section.
    private func rig(_ count: Int) throws -> (DictationsModel, DictationStore, URL) {
        let dir = FileManager.default.temporaryDirectory.appending(path: "dictations-model-\(UUID().uuidString)")
        var model: DictationsModel?
        let store = DictationStore(file: dir.appending(path: "dictations.sqlite")) { model?.reload() }
        for i in 0..<count { try store.add(text: "entry \(i)", app: nil, at: start.addingTimeInterval(Double(i) * 60)) }
        let defaults = try defaults()
        defaults.set("all", forKey: "dictationsPeriod")
        model = DictationsModel(store: store, defaults: defaults)
        return (try #require(model), store, dir)
    }

    private func defaults() throws -> UserDefaults {
        try #require(UserDefaults(suiteName: "dictations-model-\(UUID().uuidString)"))
    }

    @Test func aPeriodListsOnlyItsDictationsAndIsRemembered() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "dictations-model-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = DictationStore(file: dir.appending(path: "dictations.sqlite"))
        let now = Date()
        try store.add(text: "old", app: nil, at: now.addingTimeInterval(-40 * 86_400))
        try store.add(text: "this week", app: nil, at: now.addingTimeInterval(-3 * 86_400))
        try store.add(text: "now", app: nil, at: now)
        let defaults = try defaults()
        let model = DictationsModel(store: store, defaults: defaults)
        #expect(model.period == .month)
        model.reload()
        #expect(model.entries.map(\.text) == ["now", "this week"])
        model.period = .today
        #expect(model.entries.map(\.text) == ["now"])
        model.period = .all
        #expect(model.entries.map(\.text) == ["now", "this week", "old"])
        #expect(DictationsModel(store: store, defaults: defaults).period == .all)
    }

    @Test func theFirstPageThenTheNextWhenTheLastRowsAppear() throws {
        let (model, _, dir) = try rig(450)
        defer { try? FileManager.default.removeItem(at: dir) }
        model.reload()
        #expect(model.entries.count == 200)
        #expect(model.entries.first?.text == "entry 449")
        model.appeared(model.entries[100].id) // not near the end
        #expect(model.entries.count == 200)
        model.appeared(model.entries[185].id)
        #expect(model.entries.count == 400)
        model.appeared(model.entries[399].id)
        #expect(model.entries.count == 450)
        #expect(model.entries.last?.text == "entry 0")
        model.appeared(model.entries[449].id) // nothing older
        #expect(model.entries.count == 450)
        #expect(Set(model.entries.map(\.id)).count == 450)
        let lines = model.lines.map(\.id)
        #expect(lines.filter { if case .entry = $0 { true } else { false } }.count == 450)
        #expect(Set(lines).count == lines.count) // a day that goes on into the next page has one title
    }

    @Test func aNewDictationComesAtTheTopAndTheLoadedRowsStay() throws {
        let (model, store, dir) = try rig(300)
        defer { try? FileManager.default.removeItem(at: dir) }
        model.reload()
        model.appeared(model.entries[199].id)
        let open = model.entries[250].id
        model.toggle(open)
        try store.add(text: "new", app: AppRef(bundleID: "com.tinyspeck.slackmacgap", name: "Slack"), at: start.addingTimeInterval(1e6))
        #expect(model.entries.count == 300)
        #expect(model.entries.first?.text == "new")
        #expect(model.open == [open])
        model.appeared(model.entries[299].id)
        #expect(model.entries.count == 301)
        #expect(model.entries.last?.text == "entry 0")
    }

    @Test func aClickOpensARowAndAnotherClosesIt() throws {
        let (model, _, dir) = try rig(2)
        defer { try? FileManager.default.removeItem(at: dir) }
        model.reload()
        let id = model.entries[0].id
        model.toggle(id)
        #expect(model.open == [id])
        model.toggle(id)
        #expect(model.open.isEmpty)
    }

    @Test func deleteRemovesTheEntry() throws {
        let (model, store, dir) = try rig(3)
        defer { try? FileManager.default.removeItem(at: dir) }
        model.reload()
        let gone = model.entries[1]
        model.toggle(gone.id)
        model.delete(gone)
        #expect(model.entries.map(\.text) == ["entry 2", "entry 0"])
        #expect(model.open.isEmpty)
        #expect(try store.page(limit: 10).map(\.text) == ["entry 2", "entry 0"])
        #expect(model.notice == nil)
    }

    @Test func aClearedHistoryEmptiesTheList() throws {
        let (model, store, dir) = try rig(3)
        defer { try? FileManager.default.removeItem(at: dir) }
        model.reload()
        model.toggle(model.entries[0].id)
        try store.clear()
        #expect(model.entries.isEmpty && model.lines.isEmpty && model.open.isEmpty)
    }
}
