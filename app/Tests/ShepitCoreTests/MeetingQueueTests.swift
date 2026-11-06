import Foundation
import Testing
@testable import ShepitCore

// Spec §5.3 and §5.4 "Chronological order".
struct MeetingQueueTests {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    private func at(_ seconds: Double) -> Date { t0.addingTimeInterval(seconds) }

    private func chunk(_ stream: MeetingStream, _ start: Double, _ end: Double) -> MeetingChunk {
        MeetingChunk(stream: stream, start: Int(start * 16_000), end: Int(end * 16_000), wallStart: at(start), samples: [])
    }

    private func entry(_ stream: MeetingStream, _ start: Double, _ text: String) -> MeetingEntry {
        MeetingEntry(stream: stream, wallStart: at(start), offsets: start..<(start + 1), text: text)
    }

    private func texts(_ entries: [MeetingEntry]) -> [String] { entries.map(\.text) }

    @Test func chunksComeOutOldestFirstOneAtATime() throws {
        var queue = MeetingQueue()
        queue.add(chunk(.call, 5, 8))
        queue.add(chunk(.mine, 2, 4))
        let firstNext = queue.next()
        let first = try #require(firstNext)
        #expect(first.stream == .mine)
        let none = queue.next()
        #expect(none == nil) // one in flight
        #expect(queue.waiting == 2)
        queue.done(first.id, entries: [])
        let second = queue.next()
        #expect(second?.stream == .call)
        #expect(queue.waiting == 1)
    }

    @Test func anEntryWaitsForAnEarlierOpenPhraseOnTheOtherStream() throws {
        var queue = MeetingQueue()
        queue.setFrontier(.call, at(3)) // the call has an open phrase from 3 s
        queue.setFrontier(.mine, nil)
        queue.add(chunk(.mine, 5, 6))
        let mineNext = queue.next()
        let mine = try #require(mineNext)
        queue.done(mine.id, entries: [entry(.mine, 5, "так")])
        #expect(queue.ready().isEmpty)

        queue.add(chunk(.call, 3, 9))
        queue.setFrontier(.call, at(9.5))
        let callNext = queue.next()
        let call = try #require(callNext)
        #expect(queue.ready().isEmpty) // the call chunk is in flight and starts earlier
        queue.done(call.id, entries: [entry(.call, 3, "питання"), entry(.call, 7, "далі")])
        #expect(texts(queue.ready()) == ["питання", "так", "далі"])
        #expect(queue.ready().isEmpty)
    }

    @Test func entriesAtOrBeforeTheFrontierAreReleased() throws {
        var queue = MeetingQueue()
        queue.setFrontier(.mine, at(10))
        queue.setFrontier(.call, at(4))
        queue.add(chunk(.call, 1, 3))
        let callNext = queue.next()
        let call = try #require(callNext)
        queue.done(call.id, entries: [entry(.call, 1, "a"), entry(.call, 4, "b"), entry(.call, 5, "c")])
        #expect(texts(queue.ready()) == ["a", "b"])
        queue.setFrontier(.call, at(20))
        #expect(texts(queue.ready()) == ["c"])
    }

    @Test func entriesFromOneChunkKeepTheirOrderWithinTheSameSecond() throws {
        var queue = MeetingQueue()
        queue.setFrontier(.mine, nil)
        queue.setFrontier(.call, nil)
        queue.add(chunk(.call, 1, 3))
        let callNext = queue.next()
        let call = try #require(callNext)
        queue.done(call.id, entries: [entry(.call, 1, "перше"), entry(.call, 1, "друге")])
        #expect(texts(queue.ready()) == ["перше", "друге"])
    }

    @Test func aFailedChunkBecomesAVisibleEntry() throws {
        var queue = MeetingQueue()
        queue.setFrontier(.mine, nil)
        queue.setFrontier(.call, nil)
        queue.add(chunk(.call, 2, 6))
        let callNext = queue.next()
        let call = try #require(callNext)
        queue.failed(call.id)
        let entries = queue.ready()
        #expect(entries == [MeetingEntry(stream: .call, wallStart: at(2), offsets: 2..<6, text: "⚠ не вдалося розпізнати", failed: true)])
    }

    @Test func aStoppedStreamNoLongerBlocks() throws {
        var queue = MeetingQueue()
        queue.setFrontier(.mine, at(1))
        queue.setFrontier(.call, nil)
        queue.add(chunk(.call, 4, 5))
        let callNext = queue.next()
        let call = try #require(callNext)
        queue.done(call.id, entries: [entry(.call, 4, "x")])
        #expect(queue.ready().isEmpty)
        queue.setFrontier(.mine, nil) // microphone capture died
        #expect(texts(queue.ready()) == ["x"])
    }

    @Test func atStopEverythingIsReleasedInOrder() throws {
        var queue = MeetingQueue()
        queue.setFrontier(.mine, at(0))
        queue.setFrontier(.call, at(0))
        queue.add(chunk(.mine, 6, 7))
        queue.add(chunk(.call, 1, 4))
        while let next = queue.next() {
            queue.done(next.id, entries: [entry(next.stream, Double(next.start) / 16_000, next.stream == .mine ? "m" : "c")])
        }
        #expect(queue.ready().isEmpty)
        queue.setFrontier(.mine, nil)
        queue.setFrontier(.call, nil)
        #expect(texts(queue.ready()) == ["c", "m"])
        #expect(queue.waiting == 0)
    }

    @Test func releaseAllGivesEveryRecognizedEntryInOrder() throws {
        var queue = MeetingQueue()
        queue.setFrontier(.mine, at(0))
        queue.add(chunk(.call, 1, 2))
        let callNext = queue.next()
        let call = try #require(callNext)
        queue.done(call.id, entries: [entry(.call, 3, "b"), entry(.call, 1, "a")])
        queue.add(chunk(.mine, 0.5, 1)) // still queued
        #expect(queue.ready().isEmpty)
        #expect(texts(queue.releaseAll()) == ["a", "b"])
        #expect(queue.releaseAll().isEmpty)
    }

    // Echo on speakers (Task 11, Test4): the mic hears the call.

    private func recognized(_ queue: inout MeetingQueue, _ entries: [MeetingEntry]) throws {
        for e in entries {
            queue.add(MeetingChunk(stream: e.stream, start: 0, end: 1, wallStart: e.wallStart, samples: []))
            let next = queue.next()
            let chunk = try #require(next)
            queue.done(chunk.id, entries: [e])
        }
    }

    @Test func aMicEntryRepeatingTheCallIsDropped() throws {
        var queue = MeetingQueue(echoWindow: 5)
        queue.setFrontier(.mine, nil)
        queue.setFrontier(.call, nil)
        try recognized(&queue, [entry(.mine, 22, "Mr. Veles."), entry(.call, 22.5, "Mr. Velas, this is Dr. Sharp."),
                                entry(.call, 40, "We grew up a town apart in La Isla but never knew each other"),
                                entry(.mine, 40.5, "We grew up a town apart in La Isla"),
                                entry(.mine, 60, "Зараз ми пишемо українською"), entry(.call, 61, "You guys have the best service")])
        #expect(texts(queue.ready()) == ["Mr. Velas, this is Dr. Sharp.", "We grew up a town apart in La Isla but never knew each other",
                                         "Зараз ми пишемо українською", "You guys have the best service"])
    }

    @Test func anEchoIsCaughtWhenTheCallEntryWasReleasedFirst() throws {
        var queue = MeetingQueue(echoWindow: 5)
        queue.setFrontier(.mine, at(0))
        queue.setFrontier(.call, nil)
        try recognized(&queue, [entry(.call, 1, "We're like brothers")])
        queue.setFrontier(.mine, at(7))
        #expect(texts(queue.ready()) == ["We're like brothers"])
        try recognized(&queue, [entry(.mine, 3, "we're like brothers")])
        queue.setFrontier(.mine, nil)
        #expect(queue.ready().isEmpty)
    }

    @Test func entriesWaitTheEchoWindowSoALaterCallPhraseCanMatch() throws {
        var queue = MeetingQueue(echoWindow: 5)
        queue.setFrontier(.mine, nil)
        queue.setFrontier(.call, at(4)) // the call's phrase from 4 s is still open
        try recognized(&queue, [entry(.mine, 2, "I thought you guys were brothers")])
        #expect(queue.ready().isEmpty) // 2 + 5 > 4
        queue.setFrontier(.call, at(20))
        try recognized(&queue, [entry(.call, 4, "I thought you guys were brothers")])
        #expect(texts(queue.ready()) == ["I thought you guys were brothers"])
    }

    @Test func myShortRepliesAndFarAwayRepeatsAreKept() throws {
        var queue = MeetingQueue(echoWindow: 5)
        queue.setFrontier(.mine, nil)
        queue.setFrontier(.call, nil)
        try recognized(&queue, [entry(.call, 0, "Так, добре, тоді завтра"), entry(.mine, 2, "Так, дякую"), entry(.mine, 3, "і мене може додати"),
                                entry(.mine, 30, "Тоді завтра")])
        #expect(texts(queue.ready()) == ["Так, добре, тоді завтра", "Так, дякую", "і мене може додати", "Тоді завтра"])
    }
}
