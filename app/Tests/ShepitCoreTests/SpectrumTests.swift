import Foundation
import Testing
@testable import ShepitCore

private func tone(_ freq: Double, _ n: Int, _ amp: Double) -> [Float] {
    // Quantised to 16-bit like the Lua test's PCM, then back to Float.
    (0..<n).map { Float(floor(amp * 32_767 * sin(2 * .pi * freq * Double($0) / 16_000))) / 32_768 }
}

private func argmax(_ values: [Float]) -> Int {
    values.indices.max { values[$0] < values[$1] }! + 1 // 1-based like the Lua test
}

// Ported from tests/test_spectrum.lua and the pick/isVirtual cases of tests/test_recorder_args.lua.
struct SpectrumTests {
    @Test func bandEdgesAreLogSpacedAcrossTheVoiceRange() {
        let edges = Spectrum.edges(10, low: 150, high: 4000)
        #expect(edges.count == 11)
        #expect(edges[0] == 150)
        #expect(abs(edges[10] - 4000) < 1e-6)
        #expect(edges[1] / edges[0] - edges[10] / edges[9] < 1e-9)
    }

    @Test func silenceGivesAllZeros() {
        #expect(Spectrum.bands([Float](repeating: 0, count: 1024), count: 10) == [Float](repeating: 0, count: 10))
    }

    @Test func emptyOrTinyInputGivesZeros() {
        #expect(Spectrum.bands([], count: 10) == [Float](repeating: 0, count: 10))
        #expect(Spectrum.bands([0.1], count: 3) == [0, 0, 0])
    }

    @Test func aLowToneLightsALowBandAHighToneAHighBand() {
        #expect(argmax(Spectrum.bands(tone(200, 1024, 0.5), count: 10)) <= 2)
        #expect(argmax(Spectrum.bands(tone(3000, 1024, 0.5), count: 10)) >= 9)
    }

    @Test func aToneLightsMainlyItsOwnBand() {
        let edges = Spectrum.edges(10, low: 150, high: 4000)
        let bands = Spectrum.bands(tone((edges[4] * edges[5]).squareRoot(), 1024, 0.5), count: 10)
        #expect(argmax(bands) == 5)
        #expect(bands[4] > 0.5)
        #expect(bands[0] < bands[4] * 0.5 && bands[9] < bands[4] * 0.5)
    }

    @Test func valuesAreNormalizedToZeroOneOnALogScale() {
        let loud = Spectrum.bands(tone(500, 1024, 1.0), count: 10)
        let quiet = Spectrum.bands(tone(500, 1024, 0.01), count: 10)
        #expect(loud.allSatisfy { $0 >= 0 && $0 <= 1 })
        let i = argmax(loud) - 1
        #expect(quiet[i] > 0.1)
        #expect(quiet[i] < loud[i])
    }

    @Test func smoothingFastAttackSlowRelease() {
        let out = Spectrum.smooth([0, 1], [1, 0])
        #expect(out[0] >= 0.6)
        #expect(out[1] > 0.7 && out[1] < 1)
    }

    @Test func smoothingWithNoPreviousFrameReturnsTheTarget() {
        #expect(Spectrum.smooth(nil, [0.3, 0.7]) == [0.3, 0.7])
    }

    // Microphone choice

    @Test func pickConfiguredDevicePresentUsesIt() {
        #expect(Microphones.pick("MOMENTUM 4", available: ["MOMENTUM 4", "MacBook Pro Microphone"]) == .init(device: "MOMENTUM 4", notice: nil))
    }

    @Test func pickConfiguredDeviceMissingUsesDefaultWithANotice() {
        #expect(Microphones.pick("AirPods", available: ["MacBook Pro Microphone"])
            == .init(device: nil, notice: #"Microphone "AirPods" not found — using the system default"#))
    }

    @Test func pickNoConfiguredDeviceUsesDefaultWithoutNotice() {
        #expect(Microphones.pick("", available: ["MacBook Pro Microphone"]) == .init(device: nil, notice: nil))
    }

    @Test func isVirtualHidesMeetingAppLoopbackDevices() {
        #expect(Microphones.isVirtual(name: "Microsoft Teams Audio", uid: "MSLoopbackDriverDevice_UID"))
        #expect(Microphones.isVirtual(name: "ZoomAudioDevice", uid: "zoom.us.zoomaudiodevice.001"))
        #expect(Microphones.isVirtual(name: "BlackHole 2ch", uid: "BlackHole2ch_UID"))
        #expect(!Microphones.isVirtual(name: "MacBook Pro Microphone", uid: "BuiltInMicrophoneDevice"))
        #expect(!Microphones.isVirtual(name: "MOMENTUM 4", uid: "80-C3-BA-86-2A-01:input"))
    }
}
