import SwiftUI
import ShepitCore

/// The window's content: the sidebar and the chosen section (window shell design §4).
struct MainView: View {
    let model: SettingsModel
    let actions: WindowActions
    let live: WindowModel
    let sections: WindowSections
    @Bindable var navigation: WindowNavigation

    var body: some View {
        NavigationSplitView {
            List(selection: Binding(get: { navigation.section }, set: { navigation.section = $0 ?? navigation.section })) {
                ForEach(WindowSection.allCases.filter { $0 != .settings }) { row($0) }
                Divider()
                row(.settings)
            }
            // The card and Home read `live` themselves: the meeting clock then redraws them, not the whole window.
            .safeAreaInset(edge: .top) {
                RecordingCard(live: live) {
                    navigation.section = .meetings
                    sections.meetings.selection = .running
                }
            }
            .navigationSplitViewColumnWidth(190)
        } detail: {
            VStack(alignment: .leading, spacing: 0) {
                ProblemBanner(model: model, actions: actions)
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
            HomeSection(model: model, actions: actions, live: live, navigation: navigation)
        case .meetings:
            MeetingsView(model: sections.meetings, actions: actions)
        case .dictations:
            DictationsView(model: sections.dictations, settings: model, actions: actions) { navigation.openSettings(.historyPrivacy) }
        case .dictionary:
            DictionarySection(model: model, actions: actions)
        case .people:
            PeopleView(model: sections.people, settings: model) {
                navigation.section = .meetings
                sections.meetings.selection = .meeting($0)
            }
        case .statistics:
            StatisticsView(model: sections.statistics, settings: model) { navigation.openSettings(.historyPrivacy) }
        case .settings:
            SettingsView(model: model, actions: actions, section: $navigation.settingsSection)
        }
    }
}

/// The running transcript, at the top of the sidebar; a click opens it in Meetings. Nothing without one.
private struct RecordingCard: View {
    let live: WindowModel
    let open: () -> Void

    var body: some View {
        if let card = live.home.card {
            button(card)
        }
    }

    private func button(_ card: Home.Card) -> some View {
        Button(action: open) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Circle().fill(.red).frame(width: 8, height: 8)
                    Text(card.headline).fontWeight(.semibold).monospacedDigit()
                }
                if !card.detail.isEmpty { Text(card.detail).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
            .background(.background, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.separator))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 10)
        .padding(.bottom, 6)
    }
}

/// settings.json errors (controls are read-only until the file is fixed) and refused writes.
private struct ProblemBanner: View {
    let model: SettingsModel
    let actions: WindowActions

    var body: some View {
        let lines = model.errors + model.dictionaryErrors + (model.lastError.map { [$0] } ?? [])
        if !lines.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(lines, id: \.self) { Text("⚠ \($0)") }
                if model.isReadOnly || model.dictionaryIsReadOnly {
                    HStack {
                        Text("Fix the file to change these settings here.")
                        if model.isReadOnly { Button("Open settings file", action: actions.openSettingsFile) }
                        if model.dictionaryIsReadOnly { Button("Open dictionary file", action: actions.openDictionaryFile) }
                    }
                }
            }
            .font(.callout)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.orange.opacity(0.15))
        }
    }
}
