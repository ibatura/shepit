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

    var body: some View {
        NavigationSplitView(columnVisibility: Binding(get: { navigation.sidebarCollapsed ? .detailOnly : .all },
                                                      set: { navigation.sidebarCollapsed = $0 == .detailOnly })) {
            sidebar
                .navigationSplitViewColumnWidth(190)
                .toolbar(removing: .sidebarToggle)
        } detail: {
            HStack(spacing: 0) {
                if navigation.sidebarCollapsed {
                    VStack(spacing: 0) {
                        RecordingCard(live: live, collapsed: true, open: openRunning)
                        SectionIcons(navigation: navigation)
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
                ToolbarItemGroup(placement: .navigation) {
                    Button { navigation.sidebarCollapsed.toggle() } label: { Label("Sidebar", systemImage: "sidebar.left") }
                        .help(navigation.sidebarCollapsed ? "Show the sidebar" : "Collapse the sidebar to its icons")
                        .keyboardShortcut("s", modifiers: [.control, .command])
                    BackForwardButtons(navigation: navigation)
                }
            }
        }
    }

    private var sidebar: some View {
        List(selection: Binding(get: { navigation.section }, set: { navigation.section = $0 ?? navigation.section })) {
            ForEach(WindowSection.allCases.filter { $0 != .settings }) { row($0) }
            Divider()
            row(.settings)
        }
        .listStyle(.sidebar)
        // The card and Home read `live` themselves: the meeting clock then redraws them, not the whole window.
        .safeAreaInset(edge: .top) { RecordingCard(live: live, collapsed: false, open: openRunning) }
    }

    private func row(_ section: WindowSection) -> some View {
        Label(section.rawValue, systemImage: section.symbol).tag(section)
    }

    private func openRunning() {
        navigation.section = .meetings
        sections.meetings.selection = .running
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

/// The collapsed sidebar: the sections' icons in a column, each with its name as a hint (back and forward design §10).
private struct SectionIcons: View {
    let navigation: WindowNavigation

    var body: some View {
        VStack(spacing: 2) {
            ForEach(WindowSection.allCases.filter { $0 != .settings }) { icon($0) }
            Divider().padding(.horizontal, 12).padding(.vertical, 6)
            icon(.settings)
            Spacer()
        }
        .padding(.top, 8)
    }

    private func icon(_ section: WindowSection) -> some View {
        let chosen = navigation.section == section
        return Button { navigation.section = section } label: {
            Image(systemName: section.symbol)
                .font(.system(size: 15))
                .foregroundStyle(chosen ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                .frame(width: 36, height: 30)
                .background(chosen ? Color.primary.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 7))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(section.rawValue)
        .accessibilityLabel(section.rawValue)
        .accessibilityAddTraits(chosen ? .isSelected : [])
    }
}

/// ‹ and ›, ⌘[ and ⌘], with a hint on where each goes (back and forward design §6). Every change of place is recorded
/// here too: in a view of its own, a new choice in a section (and the meeting clock, read for a step to the running
/// transcript) redraws these two buttons, not the whole window.
private struct BackForwardButtons: View {
    let navigation: WindowNavigation

    var body: some View {
        Button(action: navigation.back) { Label("Back", systemImage: "chevron.left") }
            .disabled(!navigation.canGoBack)
            .help(navigation.backHint)
            .keyboardShortcut("[", modifiers: .command)
            // initial: the window can first appear on a place set while it was closed (Settings… from the menu).
            .onChange(of: navigation.place, initial: true) { navigation.visit($1) }
        Button(action: navigation.forward) { Label("Forward", systemImage: "chevron.right") }
            .disabled(!navigation.canGoForward)
            .help(navigation.forwardHint)
            .keyboardShortcut("]", modifiers: .command)
    }
}

/// The running transcript, at the top of the sidebar; a click opens it in Meetings. Nothing without one. In the collapsed
/// sidebar a red dot, with the card's text as its hint.
private struct RecordingCard: View {
    let live: WindowModel
    let collapsed: Bool
    let open: () -> Void

    var body: some View {
        if let card = live.home.card {
            if collapsed {
                Button(action: open) { Circle().fill(.red).frame(width: 10, height: 10).frame(maxWidth: .infinity).padding(.vertical, 8) }
                    .buttonStyle(.plain)
                    .help([card.headline, card.detail].filter { !$0.isEmpty }.joined(separator: " · "))
            } else {
                button(card)
            }
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
