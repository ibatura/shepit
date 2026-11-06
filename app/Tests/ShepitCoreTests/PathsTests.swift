import Testing
import Foundation
@testable import ShepitCore

struct PathsTests {
    @Test func dictationHomeOverrides() {
        let paths = Paths.resolve(environment: ["DICTATION_HOME": "/tmp/x", "HOME": "/Users/ignored"])

        #expect(paths.settingsFile.path == "/tmp/x/.config/dictation/settings.json")
        #expect(paths.modelsDir.path == "/tmp/x/.local/share/dictation/models")
    }
}
