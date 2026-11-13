import AppKit
import ShepitCore

/// The status item: title from MenuModel, menu rebuilt from MenuModel each time it opens.
@MainActor
final class MenuController: NSObject, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()
    private let currentView: () -> AppSnapshot
    private let titleView: () -> AppSnapshot
    private let perform: (AppAction) -> Void
    private var actions: [AppAction] = [] // indexed by NSMenuItem.tag

    /// `view` is called when the menu opens and looks devices and files up again; `title` is refreshed often and reuses them.
    init(view: @escaping () -> AppSnapshot, title: @escaping () -> AppSnapshot, perform: @escaping (AppAction) -> Void) {
        currentView = view
        titleView = title
        self.perform = perform
        super.init()
        menu.delegate = self
        menu.autoenablesItems = false
        statusItem.menu = menu
        refreshTitle()
    }

    func refreshTitle() {
        let view = titleView()
        statusItem.button?.title = MenuModel.title(view)
        statusItem.button?.toolTip = "Shepit: \(view.statusLine)"
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        let view = currentView()
        actions = []
        menu.removeAllItems()
        for item in MenuModel.build(view) { menu.addItem(make(item)) }
        statusItem.button?.title = MenuModel.title(view)
    }

    private func make(_ item: MenuItem) -> NSMenuItem {
        if item == .separator { return .separator() }
        let menuItem = NSMenuItem(title: item.title, action: nil, keyEquivalent: item.keyEquivalent)
        menuItem.isEnabled = item.enabled
        menuItem.state = item.checked ? .on : .off
        menuItem.toolTip = item.tooltip
        if let action = item.action {
            menuItem.target = self
            menuItem.action = #selector(clicked(_:))
            menuItem.tag = actions.count
            actions.append(action)
        }
        if let submenu = item.submenu {
            let sub = NSMenu()
            sub.autoenablesItems = false
            for child in submenu { sub.addItem(make(child)) }
            menuItem.submenu = sub
        }
        return menuItem
    }

    @objc private func clicked(_ sender: NSMenuItem) {
        guard actions.indices.contains(sender.tag) else { return }
        perform(actions[sender.tag])
    }
}
