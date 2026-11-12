import AppKit
import ShepitCore
import SwiftUI

/// The floating card for calls (call offer design §5.5, visual style §6): top right of the screen with the
/// mouse, above other windows and full-screen apps, never takes keyboard focus. It keeps no timers: it is
/// redrawn from the state machine's panel value.
@MainActor
final class CallPanel {
    private let model = CallPanelModel()
    private var panel: NSPanel?
    private var screen: NSScreen?

    func show(_ value: CallOffer.Panel, onMain: @escaping () -> Void, onOther: @escaping () -> Void) {
        model.show(value.text, onMain: onMain, onOther: onOther)
        let panel = ensurePanel()
        // It stays on the screen it appeared on.
        if !panel.isVisible { screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main }
        guard let visible = screen?.visibleFrame, let size = panel.contentView?.fittingSize else { return }
        panel.setFrame(NSRect(x: visible.maxX - size.width - 16, y: visible.maxY - size.height - 16, width: size.width, height: size.height),
                       display: true)
        panel.orderFrontRegardless()
    }

    func hide() {
        panel?.orderOut(nil)
        model.text = nil
    }

    private func ensurePanel() -> NSPanel {
        if let panel { return panel }
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        panel.becomesKeyOnlyIfNeeded = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.contentView = FirstClickHostingView(rootView: CallPanelView(model: model))
        self.panel = panel
        return panel
    }
}

/// A click on a button works while another app is active.
private final class FirstClickHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

@MainActor
private final class CallPanelModel: ObservableObject {
    @Published var text: CallOffer.Panel.Text?
    /// The countdown's first value in this state: the full width of the bar.
    @Published var total = 0
    var onMain: () -> Void = {}
    var onOther: () -> Void = {}

    func show(_ new: CallOffer.Panel.Text, onMain: @escaping () -> Void, onOther: @escaping () -> Void) {
        let sameState = text?.main == new.main && text?.seconds != nil
        total = max(sameState ? total : 0, new.seconds ?? 0)
        text = new
        self.onMain = onMain
        self.onOther = onOther
    }
}

private struct CallPanelView: View {
    @ObservedObject var model: CallPanelModel

    var body: some View {
        if let text = model.text {
            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(text.title).font(.headline).lineLimit(1)
                    Text(text.status).font(.subheadline).foregroundStyle(.secondary).lineLimit(1).monospacedDigit()
                }
                if let seconds = text.seconds, model.total > 0 {
                    ProgressView(value: Double(seconds), total: Double(model.total))
                        .progressViewStyle(.linear)
                        .animation(.linear(duration: 1), value: seconds)
                }
                HStack {
                    Spacer()
                    Button(text.other) { model.onOther() }
                    Button(text.main) { model.onMain() }.buttonStyle(.borderedProminent)
                }
            }
            .padding(14)
            .frame(width: 320)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        }
    }
}

/// `Shepit panel-test`: shows each state of the panel for a few seconds, for looking at it without a call.
enum CallPanelTest {
    @MainActor static func run() {
        let application = NSApplication.shared
        application.setActivationPolicy(.accessory)
        let panel = CallPanel()
        func count(from: Int, to: Int) -> [Int] { Array(stride(from: from, through: to, by: -1)) }
        let states: [CallOffer.Panel] =
            count(from: 15, to: 10).map { .offer(title: "Weekly sync", app: .teams, hidesIn: $0) }
            + Array(repeating: .offer(title: "Zoom call", app: .zoom, hidesIn: nil), count: 3)
            + count(from: 5, to: 0).map { .autoStart(title: "Meet call", app: .meet, startsIn: $0) }
            + count(from: 10, to: 5).map { .ended(stopsIn: $0) }
            + Array(repeating: .ready(detail: "42 min · 3 people"), count: 4)
        Task { @MainActor in
            for state in states {
                panel.show(state, onMain: { print("main button: \(state.text.main)") }, onOther: { print("other button: \(state.text.other)") })
                try? await Task.sleep(for: .seconds(1))
            }
            panel.hide()
            exit(0)
        }
        application.run()
    }
}
