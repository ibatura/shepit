import SwiftUI
import ShepitCore

/// The window's content: the sidebar and the chosen section (window shell design §4). `NavigationSplitView` can only
/// hide its sidebar, so a collapsed one is that sidebar hidden and its icons in a column of the section's side
/// (back and forward design §10).
struct MainView: View {
    let model: SettingsModel
    let actions: WindowActions
    let live: WindowModel
    let sections: WindowSections
    @Bindable var navigation: WindowNavigation
    /// The section list with the keyboard focus, by `iconsOnly`. A list without it shows its selection grey.
    @FocusState private var focusedList: Bool?

    var body: some View {
        NavigationSplitView(columnVisibility: Binding(get: { navigation.sidebarCollapsed ? .detailOnly : .all },
                                                      set: { collapse($0 == .detailOnly) })) { // the divider dragged
            // The card and Home read `live` themselves: the meeting clock then redraws them, not the whole window.
            SectionList(navigation: navigation, iconsOnly: false)
                .focused($focusedList, equals: false)
                .safeAreaInset(edge: .top) { RecordingCard(live: live, open: openRunning) }
                .navigationSplitViewColumnWidth(190)
                .toolbar(removing: .sidebarToggle)
        } detail: {
            HStack(spacing: 0) {
                if navigation.sidebarCollapsed {
                    VStack(spacing: 0) {
                        RecordingDot(live: live, open: openRunning)
                        SectionList(navigation: navigation, iconsOnly: true)
                            .focused($focusedList, equals: true)
                    }
                    .frame(width: 52)
                    Divider()
                }
                VStack(alignment: .leading, spacing: 0) {
                    ProblemBanner(model: model, actions: actions)
                    section
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .navigationTitle(navigation.section.rawValue)
            .toolbar {
                ToolbarItemGroup(placement: .navigation) { WindowButtons(navigation: navigation) { collapse(!navigation.sidebarCollapsed) } }
            }
        }
    }

    /// The list shown next takes the focus if the one hidden had it; AppKit would give it to the section's first text
    /// field (back and forward design §10).
    private func collapse(_ collapsed: Bool) {
        guard collapsed != navigation.sidebarCollapsed else { return }
        let refocus = focusedList != nil
        navigation.sidebarCollapsed = collapsed
        if refocus { Task { focusedList = collapsed } } // the icons column is there on the next turn
    }

    private func openRunning() {
        navigation.section = .meetings
        sections.meetings.selection = .running
    }

    @ViewBuilder private var section: some View {
        switch navigation.section {
        case .home:
            HomeSection(actions: actions, live: live, navigation: navigation)
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

/// The sections, Settings apart below a divider. With icons only it is the collapsed sidebar, each name a hint
/// (back and forward design §10).
private struct SectionList: View {
    let navigation: WindowNavigation
    let iconsOnly: Bool

    var body: some View {
        List(selection: Binding(get: { navigation.section }, set: { navigation.section = $0 ?? navigation.section })) {
            ForEach(WindowSection.allCases.filter { $0 != .settings }) { row($0) }
            Divider()
            row(.settings)
        }
        .listStyle(.sidebar)
    }

    @ViewBuilder private func row(_ section: WindowSection) -> some View {
        let label = Label(section.rawValue, systemImage: section.symbol)
        if iconsOnly {
            label.labelStyle(.iconOnly).help(section.rawValue).tag(section)
        } else {
            label.tag(section)
        }
    }
}

/// The sidebar button (⌃⌘S), and ‹ and › (⌘[ and ⌘]) with a hint on where each goes (back and forward design §6, §10).
/// A view of its own: the hints read the meeting clock for a step to the running transcript, which then redraws only
/// these buttons.
private struct WindowButtons: View {
    @Bindable var navigation: WindowNavigation
    let toggleSidebar: () -> Void

    var body: some View {
        Button(action: toggleSidebar) { Label("Sidebar", systemImage: "sidebar.left") }
            .help(navigation.sidebarCollapsed ? "Show the sidebar" : "Collapse the sidebar to its icons")
            .keyboardShortcut("s", modifiers: [.control, .command])
        Button(action: navigation.back) { Label("Back", systemImage: "chevron.left") }
            .disabled(!navigation.canGoBack)
            .help(navigation.backHint)
            .keyboardShortcut("[", modifiers: .command)
        Button(action: navigation.forward) { Label("Forward", systemImage: "chevron.right") }
            .disabled(!navigation.canGoForward)
            .help(navigation.forwardHint)
            .keyboardShortcut("]", modifiers: .command)
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

/// The running transcript in the collapsed sidebar: a red dot with the card's text as its hint; a click opens it in
/// Meetings. Nothing without one.
private struct RecordingDot: View {
    let live: WindowModel
    let open: () -> Void

    var body: some View {
        if let card = live.home.card {
            Button(action: open) { Circle().fill(.red).frame(width: 10, height: 10).frame(maxWidth: .infinity).padding(.vertical, 8) }
                .buttonStyle(.plain)
                .help([card.headline, card.detail].filter { !$0.isEmpty }.joined(separator: " · "))
        }
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
