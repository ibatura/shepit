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
            button.image = Self.image(icon)
        }
        let status = "Shepit: \(view.statusLine)"
        button.toolTip = status
        button.setAccessibilityLabel(status) // the button has no title to read
    }

    /// B2's rhombus in 18×18 pt (the round 3 glyph): 7 columns, with a gap where B2 has its black heart.
    private nonisolated static let bars: [NSRect] = [
        (0.9, 7.8, 2.4), (3.3, 5.3, 7.4), (5.8, 3, 5.6), (5.8, 9.4, 5.6), (8.2, 0.5, 5.6),
        (8.2, 11.9, 5.6), (10.6, 3, 5.6), (10.6, 9.4, 5.6), (13.1, 5.3, 7.4), (15.5, 7.8, 2.4),
    ].map { NSRect(x: $0.0, y: $0.1, width: 1.6, height: $0.2) }

    /// Icon and name design §6. AppKit may call the drawing handler on any thread, so it captures only the icon.
    nonisolated static func image(_ icon: MenuIcon) -> NSImage {
        let side: CGFloat = 18, dot: CGFloat = 6
        let left: CGFloat = icon.meeting ? dot + 3 : 0
        let image = NSImage(size: NSSize(width: left + side, height: side), flipped: true) { _ in
            if icon.meeting {
                NSColor.systemRed.setFill()
                NSBezierPath(ovalIn: NSRect(x: 0, y: (side - dot) / 2, width: dot, height: dot)).fill()
            }
            let ink: NSColor = icon.isPlain ? .black : .labelColor // a template keeps only the alpha
            let colour = switch icon.mark {
            case .recording: NSColor.systemRed
            case .transcribing: ink.withAlphaComponent(0.4)
            case .ready, .problem: ink
            }
            let badge = NSRect(x: left + side - 5, y: 0, width: 5, height: 5)
            NSGraphicsContext.saveGraphicsState()
            if icon.mark == .problem { // 1 pt clear around the dot, so it doesn't touch the bars
                let clip = NSBezierPath(rect: NSRect(x: 0, y: 0, width: left + side, height: side))
                clip.appendOval(in: badge.insetBy(dx: -1, dy: -1))
                clip.windingRule = .evenOdd
                clip.addClip()
            }
            colour.setFill()
            for bar in bars { NSBezierPath(roundedRect: bar.offsetBy(dx: left, dy: 0), xRadius: 0.4, yRadius: 0.4).fill() }
            NSGraphicsContext.restoreGraphicsState()
            if icon.mark == .problem {
                NSColor.systemOrange.setFill()
                NSBezierPath(ovalIn: badge).fill()
            }
            return true
        }
        image.isTemplate = icon.isPlain
        return image
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

/// `Shepit menubar-test`: shows each menu bar icon for a moment, for looking at it without a dictation or a call.
/// Shepit's theme doesn't matter here: a status item has the menu bar's own appearance, whatever `NSApp.appearance` is.
enum MenuBarTest {
    @MainActor static func run() {
        let application = NSApplication.shared
        application.setActivationPolicy(.accessory)
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let icons = MenuIcon.Mark.allCases.flatMap { mark in [false, true].map { MenuIcon(mark: mark, meeting: $0) } }
        Task { @MainActor in
            for icon in icons {
                item.button?.image = MenuController.image(icon)
                print("\(icon.mark)\(icon.meeting ? ", meeting" : "")")
                try? await Task.sleep(for: .seconds(2))
            }
            exit(0)
        }
        application.run()
    }
}
