import Accelerate
import Foundation

/// Frequency bands for the level meter: Hann window + Goertzel per band (port of spectrum.lua).
public enum Spectrum {
    static let rate = 16_000.0
    static let low = 150.0
    static let high = 4000.0
    static let probes = 4 // frequencies sampled per band
    static let floorDB = -60.0 // maps to 0
    static let ceilDB = -6.0 // maps to 1
    static let attack: Float = 0.7
    static let release: Float = 0.15

    public static func edges(_ n: Int, low: Double, high: Double) -> [Double] {
        (0...n).map { low * pow(high / low, Double($0) / Double(n)) }
    }

    /// Levels 0…1 for `count` log-spaced bands of 16 kHz samples in −1…1.
    public static func bands(_ samples: [Float], count: Int) -> [Float] {
        var out = [Float](repeating: 0, count: count)
        let n = samples.count
        guard n >= 64 else { return out }
        // vDSP's Hann is periodic (2πi/n); Lua used symmetric (n−1) — no visible difference at 1024 samples.
        var window = [Float](repeating: 0, count: n)
        vDSP_hann_window(&window, vDSP_Length(n), Int32(vDSP_HANN_DENORM))
        let x = vDSP.multiply(samples, window)
        let e = edges(count, low: low, high: high)
        for band in 0..<count {
            var best = 0.0
            for k in 0..<probes {
                let freq = e[band] * pow(e[band + 1] / e[band], (Double(k) + 0.5) / Double(probes))
                best = max(best, power(x, freq))
            }
            if best > 0 {
                let db = 10 * log10(best)
                out[band] = Float(max(0, min(1, (db - floorDB) / (ceilDB - floorDB))))
            }
        }
        return out
    }

    public static func smooth(_ previous: [Float]?, _ target: [Float]) -> [Float] {
        guard let previous else { return target }
        return target.enumerated().map { i, t in
            let p = i < previous.count ? previous[i] : 0
            return p + (t - p) * (t > p ? attack : release)
        }
    }

    /// Power at one frequency (Goertzel), normalized so a full-scale sine is ~1.
    private static func power(_ x: [Float], _ freq: Double) -> Double {
        let c = 2 * cos(2 * .pi * freq / rate)
        var s1 = 0.0
        var s2 = 0.0
        for sample in x {
            let s0 = Double(sample) + c * s1 - s2
            s2 = s1
            s1 = s0
        }
        let n = Double(x.count)
        return (s1 * s1 + s2 * s2 - c * s1 * s2) / (n * n / 16) // Hann halves amplitude: (n/2 · 1/2)²
    }
}

/// Which input device to record from (port of recorder_args.lua pick / isVirtual).
public enum Microphones {
    public struct Pick: Equatable, Sendable {
        public var device: String?
        public var notice: String?
    }

    public static func pick(_ configured: String, available: [String]) -> Pick {
        guard !configured.isEmpty else { return Pick(device: nil, notice: nil) }
        if available.contains(configured) { return Pick(device: configured, notice: nil) }
        return Pick(device: nil, notice: #"Microphone "\#(configured)" not found — using the system default"#)
    }

    private static let virtualWords = ["loopback", "zoom", "teams", "blackhole", "soundflower", "aggregate"]

    /// Meeting-app loopback devices, hidden from the microphone list.
    public static func isVirtual(name: String, uid: String) -> Bool {
        let s = "\(name) \(uid)".lowercased()
        return virtualWords.contains { s.contains($0) }
    }
}
