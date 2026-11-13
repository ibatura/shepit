import SwiftUI
import ShepitCore

/// The window's content: the sidebar and the chosen section (window shell design §4).
struct MainView: View {
    let model: SettingsModel
    let actions: SettingsActions
    @Bindable var navigation: WindowNavigation

    var body: some View {
        NavigationSplitView {
            List(selection: Binding(get: { navigation.section }, set: { navigation.section = $0 ?? navigation.section })) {
                ForEach(WindowSection.allCases.dropLast()) { row($0) }
                Divider()
                row(.settings)
            }
            .navigationSplitViewColumnWidth(190)
        } detail: {
            VStack(alignment: .leading, spacing: 0) {
                ProblemBanner(model: model, openFile: actions.openSettingsFile)
                section
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .navigationTitle(navigation.section.rawValue)
        }
    }

    private func row(_ section: WindowSection) -> some View {
        Label(section.rawValue, systemImage: section.symbol).tag(section)
    }

    @ViewBuilder private var section: some View {
        switch navigation.section {
        case .home:
            Placeholder(section: .home, text: "Home comes next.")
        case .meetings:
            Placeholder(section: .meetings, text: "Meetings come in a later version. Until then they are in the menu.")
        case .dictations:
            Placeholder(section: .dictations, text: "The full history comes in a later version.", button: "Open history file", action: actions.openHistory)
        case .dictionary:
            Form { DictionarySection(model: model) }.formStyle(.grouped).disabled(model.dictionaryIsReadOnly)
        case .people:
            Placeholder(section: .people, text: "Saved voices come in a later version.")
        case .statistics:
            Form {
                StatisticsSection(model: model, actions: actions) { navigation.openSettings(.historyPrivacy) }
            }
            .formStyle(.grouped)
        case .settings:
            SettingsView(model: model, actions: actions, section: $navigation.settingsSection)
        }
    }
}

/// A section that is not built yet.
private struct Placeholder: View {
    let section: WindowSection
    let text: String
    var button: String?
    var action: () -> Void = {}

    var body: some View {
        ContentUnavailableView {
            Label(section.rawValue, systemImage: section.symbol)
        } description: {
            Text(text)
        } actions: {
            if let button { Button(button, action: action) }
        }
    }
}
