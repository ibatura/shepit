import AppKit
import ShepitCore

/// The status item: the rhombus from MenuModel.icon, the menu rebuilt from MenuModel each time it opens.
@MainActor
final class MenuController: NSObject, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()
    private let currentView: () -> AppSnapshot
    private let iconView: () -> AppSnapshot
    private let perform: (AppAction) -> Void
    private var actions: [AppAction] = [] // indexed by NSMenuItem.tag
    private var shown: MenuIcon? // the meeting's clock refreshes every second; the image is drawn again only when it changes

    /// `view` is called when the menu opens and looks devices and files up again; `icon` is refreshed often and reuses them.
    init(view: @escaping () -> AppSnapshot, icon: @escaping () -> AppSnapshot, perform: @escaping (AppAction) -> Void) {
        currentView = view
        iconView = icon
        self.perform = perform
        super.init()
        menu.delegate = self
        menu.autoenablesItems = false
        statusItem.menu = menu
        refreshIcon()
    }

    func refreshIcon() {
        show(iconView())
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        let view = currentView()
        actions = []
        menu.removeAllItems()
        for item in MenuModel.build(view) { menu.addItem(make(item)) }
        show(view)
    }

    private func show(_ view: AppSnapshot) {
        guard let button = statusItem.button else { return }
        let icon = MenuModel.icon(view)
        if icon != shown {
            shown = icon
            button.image = icon.image
        }
        let status = MenuModel.iconLabel(view)
        button.toolTip = status
        button.setAccessibilityLabel(status) // the button has no title to read
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
