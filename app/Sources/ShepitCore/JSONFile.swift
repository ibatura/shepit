import Darwin
import Foundation

/// Reading and atomically writing the JSON object files (settings.json, dictionary.json).
enum JSONFile {
    struct ReadError: Error {
        let message: String
    }

    /// A missing file reads as an empty object.
    static func readObject(_ file: URL) -> Result<[String: Any], ReadError> {
        guard FileManager.default.fileExists(atPath: file.path) else { return .success([:]) }
        do {
            let data = try Data(contentsOf: file)
            let decoded = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
            guard let object = decoded as? [String: Any], JSONSerialization.isValidJSONObject(object) else {
                return .failure(ReadError(message: "file must contain JSON object"))
            }
            return .success(object)
        } catch {
            return .failure(ReadError(message: decodingMessage(for: error)))
        }
    }

    /// Writes via a temp file + rename, so a failed write never leaves a half-written file.
    static func writeAtomically(_ raw: [String: Any], to file: URL) throws {
        guard JSONSerialization.isValidJSONObject(raw) else {
            throw SettingsStoreError.write("could not encode \(file.lastPathComponent)")
        }
        let data = try JSONSerialization.data(withJSONObject: raw, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        let file = file.resolvingSymlinksInPath() // a dotfiles symlink stays a symlink
        let temporary = file.deletingLastPathComponent()
            .appending(path: ".\(file.lastPathComponent).\(UUID().uuidString).tmp")
        do {
            try data.write(to: temporary)
            let result = temporary.path.withCString { source in
                file.path.withCString { destination in
                    Darwin.rename(source, destination)
                }
            }
            guard result == 0 else {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
        } catch {
            try? FileManager.default.removeItem(at: temporary)
            throw error
        }
    }

    private static func decodingMessage(for error: Error) -> String {
        let details = (error as NSError).userInfo["NSDebugDescription"] as? String ?? ""
        if details.contains("JSON parse") {
            let line = details.range(of: #"line (\d+)"#, options: .regularExpression)
                .flatMap { Int(details[$0].dropFirst("line ".count)) } ?? 1
            return "parse error at line \(line)"
        }
        return error.localizedDescription
    }
}
