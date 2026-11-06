import Testing
@testable import ShepitCore

struct EngineTypesTests {
    @Test func capabilityCheckAutoRequiresDetection() {
        let capabilities = EngineCapabilities(
            supportsPrompt: false,
            forcibleLanguages: [.en],
            detectsLanguage: false,
            givesSegmentTimes: false
        )

        #expect(capabilities.check(.auto) == .languageNotSupported(.auto))
    }

    @Test func capabilityCheckForcedLanguageUsesForcibleLanguages() {
        let capabilities = EngineCapabilities(
            supportsPrompt: true,
            forcibleLanguages: [.en],
            detectsLanguage: true,
            givesSegmentTimes: true
        )

        #expect(capabilities.check(.uk) == .languageNotSupported(.uk))
        #expect(capabilities.check(.en) == nil)
    }
}
