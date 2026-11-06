import Foundation

public enum LoadState: Equatable, Sendable {
    case unloaded
    case loading
    case loaded
    case failed(String)
}

/// Owns the loaded engines (`02-engines.md` §4): one instance per distinct engine+model shared by
/// the tasks that chose it, one recognition at a time per instance, dictation ahead of queued
/// draft/meeting requests, and unloading after `idleUnloadMinutes`.
public actor ModelHost {
    public typealias Factory = @Sendable (EngineChoice) throws -> any SpeechEngine

    private final class Slot {
        let engine: any SpeechEngine
        var loading: Task<Void, any Error>? // shared, so concurrent requests load once
        var loaded = false
        var lastError: String?
        var busy = false
        var waiters: [Waiter] = []
        var idleGeneration = 0

        init(engine: any SpeechEngine) {
            self.engine = engine
        }
    }

    private struct Waiter {
        let task: EngineTask
        let continuation: CheckedContinuation<Void, any Error>
    }

    private let factory: Factory
    private let sleep: @Sendable (Duration) async throws -> Void
    private let onLoad: @Sendable (EngineChoice, Double) -> Void
    private var choices: [EngineTask: EngineChoice] = [:]
    private var slots: [EngineChoice: Slot] = [:]
    private var idleMinutes = 0

    /// `onLoad` reports each completed model load and how many seconds it took (for statistics).
    public init(
        factory: @escaping Factory,
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) },
        onLoad: @escaping @Sendable (EngineChoice, Double) -> Void = { _, _ in }
    ) {
        self.factory = factory
        self.sleep = sleep
        self.onLoad = onLoad
    }

    /// Applies the settings' engine per task. A task whose old engine was loaded gets its new one
    /// loaded in the background; engines no task uses any more are unloaded.
    public func setChoices(_ new: [EngineTask: EngineChoice]) async {
        let old = choices
        choices = new
        for (task, choice) in new where old[task] != choice && old[task].flatMap({ slots[$0] }) != nil {
            Task { await self.preload(choice) }
        }
        let used = Set(new.values)
        for (choice, slot) in slots where !used.contains(choice) && !slot.busy && slot.waiters.isEmpty {
            slots[choice] = nil
            await slot.engine.unload()
        }
    }

    /// Loads the engines of these tasks (at launch: dictation and preview).
    public func preload(_ tasks: [EngineTask]) async {
        for choice in Set(tasks.compactMap { choices[$0] }) {
            await preload(choice)
        }
    }

    public func setIdleUnload(minutes: Int) {
        idleMinutes = minutes
    }

    public func loadState(_ task: EngineTask) -> LoadState {
        guard let choice = choices[task], let slot = slots[choice] else { return .unloaded }
        if slot.loaded { return .loaded }
        if slot.loading != nil { return .loading }
        return slot.lastError.map(LoadState.failed) ?? .unloaded
    }

    public func transcribe(_ task: EngineTask, _ request: TranscriptionRequest) async throws -> Transcript {
        guard let choice = choices[task] else { throw EngineError.modelMissing("no engine chosen for \(task.rawValue)") }
        let slot = try slot(for: choice)
        try await acquire(slot, for: task)
        do {
            try await ensureLoaded(slot)
            let transcript = try await slot.engine.transcribe(request)
            release(slot, choice)
            return transcript
        } catch {
            release(slot, choice)
            throw error
        }
    }

    func queuedCount(_ choice: EngineChoice) -> Int {
        slots[choice]?.waiters.count ?? 0
    }

    private func slot(for choice: EngineChoice) throws -> Slot {
        if let slot = slots[choice] { return slot }
        let slot = Slot(engine: try factory(choice))
        slots[choice] = slot
        return slot
    }

    private func preload(_ choice: EngineChoice) async {
        guard let slot = try? slot(for: choice) else { return }
        try? await ensureLoaded(slot)
    }

    private func ensureLoaded(_ slot: Slot) async throws {
        if let loading = slot.loading {
            try await loading.value
            return
        }
        let engine = slot.engine
        let started = ContinuousClock.now
        let loading = Task { try await engine.load() }
        slot.loading = loading
        do {
            try await loading.value
            let elapsed = started.duration(to: .now)
            onLoad(await engine.choice, Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18)
            slot.loaded = true
            slot.lastError = nil
        } catch {
            slot.loading = nil
            slot.lastError = String(describing: error)
            throw error
        }
    }

    private func acquire(_ slot: Slot, for task: EngineTask) async throws {
        slot.idleGeneration += 1 // a pending idle unload no longer applies
        guard slot.busy else {
            slot.busy = true
            return
        }
        if task == .preview {
            // Only the newest draft matters; an older one still waiting is dropped.
            for waiter in slot.waiters where waiter.task == .preview {
                waiter.continuation.resume(throwing: CancellationError())
            }
            slot.waiters.removeAll { $0.task == .preview }
        }
        try await withCheckedThrowingContinuation { continuation in
            let waiter = Waiter(task: task, continuation: continuation)
            if task == .dictation, let index = slot.waiters.firstIndex(where: { $0.task != .dictation }) {
                slot.waiters.insert(waiter, at: index)
            } else {
                slot.waiters.append(waiter)
            }
        }
    }

    /// Hands the engine to the next waiter (it stays busy), or frees it.
    private func release(_ slot: Slot, _ choice: EngineChoice) {
        if !slot.waiters.isEmpty {
            slot.waiters.removeFirst().continuation.resume()
            return
        }
        slot.busy = false
        if !choices.values.contains(choice) {
            slots[choice] = nil
            let engine = slot.engine
            Task { await engine.unload() }
            return
        }
        guard idleMinutes > 0 else { return }
        slot.idleGeneration += 1
        let generation = slot.idleGeneration
        let delay = Duration.seconds(idleMinutes * 60)
        let sleep = sleep
        Task {
            do { try await sleep(delay) } catch { return }
            await self.unloadIfIdle(choice, generation)
        }
    }

    private func unloadIfIdle(_ choice: EngineChoice, _ generation: Int) async {
        guard let slot = slots[choice], slot.idleGeneration == generation, !slot.busy, slot.loaded else { return }
        slot.busy = true // requests arriving during the unload wait, then load again
        slot.loading = nil
        slot.loaded = false
        await slot.engine.unload()
        if !slot.waiters.isEmpty {
            slot.waiters.removeFirst().continuation.resume()
        } else {
            slot.busy = false
        }
    }
}
