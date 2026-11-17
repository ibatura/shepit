import Foundation
import Observation
import ShepitCore

/// What the Dictations section shows (Dictations and Dictionary design §5): the store's entries, read a page at a time
/// while the section is shown, and the rows opened to their whole text. Nothing is read while the window is closed.
@MainActor
@Observable
final class DictationsModel {
    static let pageSize = 200

    /// Newest first.
    private(set) var entries: [DictationStore.Entry] = [] {
        didSet { lines = DictationPage.lines(entries, now: Date()) }
    }
    private(set) var lines: [DictationPage.Line] = []
    /// How far back the list goes; remembered in the app's preferences, like the window's section.
    var period: Period {
        didSet {
            guard period != oldValue else { return }
            defaults.set(period.rawValue, forKey: "dictationsPeriod")
            entries = []
            reload()
        }
    }
    /// Rows that show their whole text.
    private(set) var open: Set<Int> = []
    /// The entry Delete… asks about.
    var question: DictationStore.Entry?
    /// A delete that failed.
    var notice: String?

    /// Every older entry is loaded.
    @ObservationIgnored private var end = false
    @ObservationIgnored private let store: DictationStore
    @ObservationIgnored private let defaults: UserDefaults

    /// The store tells the app of every change, and the app reloads the section (`MainWindow.reload`).
    init(store: DictationStore, defaults: UserDefaults = .standard) {
        self.store = store
        self.defaults = defaults
        period = defaults.string(forKey: "dictationsPeriod").flatMap(Period.init) ?? .month
    }

    /// The newest entries again, as many as are loaded (at least a page): when the section appears, after a dictation
    /// and after Clear history…. An entry a new dictation pushed past the end comes with the next page.
    func reload() {
        let limit = max(Self.pageSize, entries.count)
        read {
            let page = try store.page(since: period.since(Date()), limit: limit)
            end = page.count < limit
            entries = page
        }
        open.formIntersection(entries.map(\.id))
    }

    /// A row came into view: the next page when it is one of the last ones.
    func appeared(_ id: Int) {
        guard !end, let last = entries.last, entries.suffix(20).contains(where: { $0.id == id }) else { return }
        read {
            let page = try store.page(before: last, since: period.since(Date()), limit: Self.pageSize)
            end = page.count < Self.pageSize
            entries += page
        }
    }

    func toggle(_ id: Int) {
        if open.remove(id) == nil { open.insert(id) }
    }

    /// The list follows through the store's change (`reload`).
    func delete(_ entry: DictationStore.Entry) {
        do {
            try store.delete(entry.id)
        } catch {
            notice = error.localizedDescription
        }
    }

    private func read(_ body: () throws -> Void) {
        do {
            try body()
        } catch {
            NSLog("Shepit dictations: %@", String(describing: error))
        }
    }
}
