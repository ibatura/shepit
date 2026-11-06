import Foundation
import ShepitCore
import Testing
@testable import ShepitEngines

private func fixture(_ name: String) throws -> [Float] {
    let url = try #require(Bundle.module.url(forResource: name, withExtension: "wav", subdirectory: "Fixtures"))
    return try AudioFile.load(url)
}

private func frames(_ samples: [Float]) -> [[Float]] {
    stride(from: 0, to: samples.count - SileroVAD.frameSamples + 1, by: SileroVAD.frameSamples).map {
        Array(samples[$0..<($0 + SileroVAD.frameSamples)])
    }
}

struct MeetingModelsTests {
    @Test func missingModelsThrowModelMissing() async throws {
        let home = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: home) }
        let paths = Paths.resolve(environment: ["DICTATION_HOME": home.path])
        #expect(throws: EngineError.modelMissing(MeetingModel.vad.folder(paths: paths).path)) { try SileroVAD(paths: paths) }
        await #expect(throws: EngineError.modelMissing(MeetingModel.diarization.folder(paths: paths).path)) {
            try await Diarizer.turns([0], paths: paths)
        }
    }

    @Test func pldaPsiRejectsABrokenFile() throws {
        let file = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: file) }
        try Data(#"{"tensors":{}}"#.utf8).write(to: file)
        #expect(throws: EngineError.self) { try Diarizer.pldaPsi(file) }
    }
}

@Suite(.enabled(if: MeetingModel.vad.isDownloaded()), .serialized)
struct SileroVADSmokeTests {
    @Test func speechFramesAreLikelyAndSilenceIsNot() async throws {
        let vad = try SileroVAD()
        var speech: [Float] = []
        for frame in frames(try fixture("hello")) { speech.append(try await vad.probability(frame)) }
        #expect(speech.contains { $0 > 0.5 })

        let quiet = try SileroVAD()
        for frame in frames([Float](repeating: 0, count: 16_000 * 3)) {
            #expect(try await quiet.probability(frame) < 0.2)
        }
    }
}

@Suite(.enabled(if: MeetingModel.diarization.isDownloaded()), .serialized)
struct DiarizerSmokeTests {
    @Test func twoVoicesGiveTwoSpeakers() async throws {
        let samples = try fixture("two-voices")
        let turns = try await Diarizer.turns(samples)
        #expect(Set(turns.map(\.speaker)).count == 2, "\(turns)")
        #expect(turns.allSatisfy { $0.start >= 0 && $0.end <= Double(samples.count) / 16_000 + 0.1 && $0.start < $0.end })
    }
}
