import Testing
@testable import ShepitCore

// Spec §5.5 steps 4–5 and §5.7 rename.
struct SpeakersTests {
    private func turn(_ speaker: String, _ start: Double, _ end: Double) -> SpeakerTurn {
        SpeakerTurn(speaker: speaker, start: start, end: end)
    }

    // assign

    @Test func largestOverlapWins() {
        let turns = [turn("S7", 0, 4), turn("S2", 4, 10)]
        #expect(Speakers.assign([3..<9], turns: turns) == ["Person 1"])
        #expect(Speakers.assign([0..<5], turns: turns) == ["Person 1"])
    }

    @Test func personsAreNumberedByFirstAppearanceNotByDiarizerID() {
        let turns = [turn("S9", 0, 5), turn("S1", 5, 10), turn("S4", 10, 15)]
        #expect(Speakers.assign([6..<9, 1..<4, 11..<14, 6..<8], turns: turns) == ["Person 1", "Person 2", "Person 3", "Person 1"])
    }

    @Test func withoutOverlapTheNearestTurnWithinTwoSecondsIsUsed() {
        let turns = [turn("A", 0, 4), turn("B", 10, 12)]
        #expect(Speakers.assign([5.5..<6], turns: turns) == ["Person 1"]) // 1.5 s after A
        #expect(Speakers.assign([8.5..<9], turns: turns) == ["Person 1"]) // 1 s before B (A is 4.5 s away)
        #expect(Speakers.assign([6.5..<7], turns: turns) == [nil]) // 2.5 s from A, 3 s from B
        #expect(Speakers.assign([1..<2], turns: []) == [nil])
    }

    @Test func nearestPicksTheCloserTurn() {
        let turns = [turn("A", 0, 4), turn("B", 7, 9)]
        #expect(Speakers.assign([1..<2, 5.5..<6.5], turns: turns) == ["Person 1", "Person 2"])
    }

    @Test func unassignedEntriesDoNotTakeANumber() {
        let turns = [turn("A", 0, 2), turn("B", 20, 22)]
        #expect(Speakers.assign([10..<11, 20..<21, 0..<1], turns: turns) == [nil, "Person 1", "Person 2"])
    }

    @Test func overlapIsSummedPerSpeakerAcrossFragmentedTurns() {
        let turns = [turn("B", 4, 7.5), turn("A", 0, 2), turn("A", 2.2, 4), turn("A", 7.5, 10)]
        #expect(Speakers.assign([0..<10], turns: turns) == ["Person 1"])
        #expect(Speakers.assign([0..<10, 4.5..<7], turns: turns) == ["Person 1", "Person 2"]) // A first, then B
    }

    @Test func equalOverlapGoesToTheEarlierSpeakerWhateverTheTurnOrder() {
        let turns = [turn("B", 5, 10), turn("A", 0, 5)]
        #expect(Speakers.assign([3..<7, 8..<9], turns: turns) == ["Person 1", "Person 2"]) // A for the tie, then B
    }

    // relabel

    private let note = """
    ---
    date: 2026-07-31
    tags: [transcript]
    ---
    [Співрозмовники] 2026-07-31 18:22:37
    перше
    [Ivan Batura] 2026-07-31 18:22:37
    моє
    [Співрозмовники] 2026-07-31 18:22:37
    друге в ту ж секунду
    [Співрозмовники] 2026-07-31 18:22:45
    третє

    """

    private let entries: [(timestamp: String, label: String?)] = [
        ("2026-07-31 18:22:37", "Person 1"),
        ("2026-07-31 18:22:37", nil), // mine
        ("2026-07-31 18:22:37", "Person 2"),
        ("2026-07-31 18:22:45", nil), // no speaker found: keeps the live label
    ]

    @Test func relabelChangesOnlyLiveHeadersMatchedByTimeAndOrder() {
        #expect(Speakers.relabel(note, live: "Співрозмовники", entries: entries) == """
        ---
        date: 2026-07-31
        tags: [transcript]
        ---
        [Person 1] 2026-07-31 18:22:37
        перше
        [Ivan Batura] 2026-07-31 18:22:37
        моє
        [Person 2] 2026-07-31 18:22:37
        друге в ту ж секунду
        [Співрозмовники] 2026-07-31 18:22:45
        третє

        """)
    }

    @Test func relabelLeavesHeadersAndTextTheUserEdited() {
        let edited = note
            .replacingOccurrences(of: "[Співрозмовники] 2026-07-31 18:22:37\nперше", with: "[Olha] 2026-07-31 18:22:37\nперше (виправлено)")
            + "Моя примітка: [Співрозмовники] 2026-07-31 18:22:37\n"
        let result = Speakers.relabel(edited, live: "Співрозмовники", entries: entries)
        #expect(result.contains("[Olha] 2026-07-31 18:22:37\nперше (виправлено)"))
        #expect(result.contains("[Person 2] 2026-07-31 18:22:37\nдруге"))
        #expect(result.hasSuffix("Моя примітка: [Співрозмовники] 2026-07-31 18:22:37\n"))
    }

    @Test func relabelIgnoresExtraHeadersWithoutAnEntry() {
        let extra = note + "[Співрозмовники] 2026-07-31 19:00:00\nдописав сам\n"
        #expect(Speakers.relabel(extra, live: "Співрозмовники", entries: entries).hasSuffix("[Співрозмовники] 2026-07-31 19:00:00\nдописав сам\n"))
    }

    @Test func aSecondWithADeletedHeaderKeepsItsLiveLabels() {
        let deleted = note.replacingOccurrences(of: "[Співрозмовники] 2026-07-31 18:22:37\nперше\n", with: "")
        let result = Speakers.relabel(deleted, live: "Співрозмовники", entries: entries)
        #expect(result.contains("[Співрозмовники] 2026-07-31 18:22:37\nдруге"))
    }

    @Test func crlfNotesAreRelabelledAndKeepTheirLineEndings() {
        let crlf = note.replacingOccurrences(of: "\n", with: "\r\n")
        let expected = Speakers.relabel(note, live: "Співрозмовники", entries: entries).replacingOccurrences(of: "\n", with: "\r\n")
        #expect(Speakers.relabel(crlf, live: "Співрозмовники", entries: entries) == expected)
        #expect(Speakers.labels(in: crlf).first?.label == "Співрозмовники")
    }

    // labels and rename

    private let labelled = """
    ---
    tags: [transcript]
    ---
    [Person 1] 2026-07-31 18:22:37
    Так.
    [Ivan Batura] 2026-07-31 18:22:40
    Добре, почнемо з плану на тиждень.
    [Person 1] 2026-07-31 18:22:45
    Мені потрібен доступ до репозиторію сьогодні.
    [Person 2] 2026-07-31 18:23:01
    Ок.

    """

    @Test func labelsInOrderOfFirstAppearanceWithASentenceLengthExample() {
        let labels = Speakers.labels(in: labelled)
        #expect(labels.map(\.label) == ["Person 1", "Ivan Batura", "Person 2"])
        #expect(labels[0].firstAt == "2026-07-31 18:22:45")
        #expect(labels[0].firstText == "Мені потрібен доступ до репозиторію сьогодні.")
        #expect(labels[2].firstAt == "2026-07-31 18:23:01") // no long entry: the first one
        #expect(labels[2].firstText == "Ок.")
    }

    @Test func renameRewritesHeadersOnlyAndMergesLabels() {
        let text = labelled + "Person 1 сказав, що [Person 1] 2026-07-31 18:22:37\n"
        let result = Speakers.rename(text, ["Person 1": "Olha Barbara", "Person 2": "Olha Barbara", "Ivan Batura": "", "Nobody": "X"])
        #expect(result.contains("[Olha Barbara] 2026-07-31 18:22:37\nТак."))
        #expect(result.contains("[Olha Barbara] 2026-07-31 18:23:01\nОк."))
        #expect(result.contains("[Ivan Batura] 2026-07-31 18:22:40"))
        #expect(result.hasSuffix("Person 1 сказав, що [Person 1] 2026-07-31 18:22:37\n"))
    }

    @Test func renameTrimsNamesAndSkipsUnchanged() {
        let result = Speakers.rename(labelled, ["Person 1": "  Olha\n Barbara \n", "Person 2": "Person 2", "Ivan Batura": " \n "])
        #expect(result.contains("[Olha Barbara] 2026-07-31 18:22:37\nТак."))
        #expect(result.contains("[Ivan Batura] 2026-07-31 18:22:40"))
        #expect(result.contains("[Person 2] 2026-07-31 18:23:01"))
    }
}
