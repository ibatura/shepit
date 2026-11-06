import Foundation

public enum Paths {
    public struct Resolved: Sendable {
        public let home: URL
        public let configDir: URL
        public let settingsFile: URL
        public let dictionaryFile: URL
        public let dataDir: URL
        public let modelsDir: URL
        public let historyFile: URL
        public let failedDir: URL
    }

    public static func resolve(environment: [String: String] = ProcessInfo.processInfo.environment) -> Resolved {
        let homePath = environment["DICTATION_HOME"] ?? environment["HOME"] ?? NSHomeDirectory()
        let home = URL(fileURLWithPath: homePath, isDirectory: true)
        let configDir = home.appending(path: ".config/dictation", directoryHint: .isDirectory)
        let dataDir = home.appending(path: ".local/share/dictation", directoryHint: .isDirectory)

        return Resolved(
            home: home,
            configDir: configDir,
            settingsFile: configDir.appending(path: "settings.json"),
            dictionaryFile: configDir.appending(path: "dictionary.json"),
            dataDir: dataDir,
            modelsDir: dataDir.appending(path: "models", directoryHint: .isDirectory),
            historyFile: dataDir.appending(path: "history.log"),
            failedDir: dataDir.appending(path: "failed", directoryHint: .isDirectory)
        )
    }

    private static let current = resolve()

    public static var home: URL { current.home }
    public static var configDir: URL { current.configDir }
    public static var settingsFile: URL { current.settingsFile }
    public static var dictionaryFile: URL { current.dictionaryFile }
    public static var dataDir: URL { current.dataDir }
    public static var modelsDir: URL { current.modelsDir }
    public static var historyFile: URL { current.historyFile }
    public static var failedDir: URL { current.failedDir }
}
