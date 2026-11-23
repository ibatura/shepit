import SwiftUI
import ShepitCore

/// The window's Dictionary section (Dictations and Dictionary design §6, mockup 5): dictionary.json's terms and drop
/// phrases as chips, replace rules edited in place, and Add word.
struct DictionarySection: View {
    let model: SettingsModel
    let actions: WindowActions

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button("Add word", action: actions.addWord)
            }
            .padding(8)
            Divider()
            Form {
                Section {
                    terms
                } header: {
                    Hinted(hint: """
                        Before recognition, engines that take a prompt (whisper.cpp, WhisperKit; not Parakeet) try to spell \
                        these words this way. They read only the first ones, with the style prompt: drag the important ones \
                        first. Dimmed ones are past that.
                        """) { Text("Terms: words the engine should know") }
                }
                Section {
                    ForEach(rules, id: \.self) { rule in
                        RuleRow(heard: rule.key, written: rule.value, model: model)
                    }
                    NewRuleRow(model: model)
                } header: {
                    Hinted(hint: """
                        After recognition, with any engine: whole words, any case, the longest phrase first. ⌃⌥D on a \
                        selected word adds a rule and a term.
                        """) { Text("Replace: heard → written") }
                }
                Section {
                    Flow {
                        ForEach(model.dictionary.dropPhrases, id: \.self) { phrase in
                            Chip(text: phrase) { model.changeDictionary { $0.dropPhrases.removeAll { $0 == phrase } } }
                        }
                        AddChip { phrase in model.changeDictionary { $0.add(dropPhrase: phrase) } }
                    }
                } header: {
                    Hinted(hint: """
                        Phrases the engine invents on silence, removed when they end a result. Common ones \
                        («Дякую за перегляд!», “Thanks for watching”) are built in.
                        """) { Text("Drop: phrases removed from every result") }
                }
            }
            .formStyle(.grouped)
        }
        .disabled(model.dictionaryIsReadOnly)
    }

    private var rules: [Rule] {
        model.dictionary.replace.map { Rule(key: $0.key, value: $0.value) }.sorted { $0.key < $1.key }
    }

    /// The terms in the file's order; a chip dropped on another takes its place.
    private var terms: some View {
        let terms = model.dictionary.terms
        let fitting = DictionaryRules.fittingTerms(style: model.settings.stylePrompt, terms: terms)
        return Flow {
            ForEach(Array(terms.enumerated()), id: \.element) { index, term in
                Chip(text: term, dimmed: index >= fitting) { model.changeDictionary { $0.terms.removeAll { $0 == term } } }
                    .draggable(term)
                    .dropDestination(for: String.self) { items, _ in
                        guard let dragged = items.first, terms.contains(dragged) else { return false }
                        model.changeDictionary { $0.move(term: dragged, to: term) }
                        return true
                    }
            }
            AddChip { term in model.changeDictionary { $0.add(term: term) } }
        }
    }

    private struct Rule: Hashable {
        var key: String
        var value: String
    }
}

/// A term or phrase; × (on hover) removes it. The × keeps its place while hidden, so the chips do not move.
private struct Chip: View {
    let text: String
    var dimmed = false
    let remove: () -> Void
    @State private var hover = false

    var body: some View {
        HStack(spacing: 3) {
            Text(text).lineLimit(1)
            Button(action: remove) { Image(systemName: "xmark.circle.fill") }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Remove")
                .opacity(hover ? 1 : 0)
        }
        .padding(.leading, 9)
        .padding(.trailing, 5)
        .padding(.vertical, 3)
        .background(.quaternary, in: Capsule())
        .opacity(dimmed ? 0.45 : 1)
        .onHover { hover = $0 }
    }
}

/// "+ add", which turns into a field: Enter adds and leaves the field open for the next one; Esc or a click elsewhere
/// closes it.
private struct AddChip: View {
    let add: (String) -> Void
    @State private var editing = false
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        if editing {
            TextField("New", text: $text)
                .textFieldStyle(.plain)
                .frame(width: 160)
                .focused($focused)
                .onAppear { focused = true }
                .onSubmit {
                    let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !value.isEmpty { add(value) }
                    text = ""
                    focused = true
                }
                .onExitCommand { focused = false }
                .onChange(of: focused) { if !focused { editing = false; text = "" } }
                .padding(.horizontal, 9)
                .padding(.vertical, 3)
                .overlay(Capsule().strokeBorder(.separator))
        } else {
            Button("+ add") { editing = true }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 9)
                .padding(.vertical, 3)
                .overlay(Capsule().strokeBorder(.separator, style: StrokeStyle(lineWidth: 1, dash: [3])))
        }
    }
}

/// A replace rule: saved on Enter or when the focus leaves the row; a refused change puts the old rule back (the
/// reason is at the top of the window).
private struct RuleRow: View {
    let heard: String
    let written: String
    let model: SettingsModel
    @State private var wrong: String
    @State private var right: String
    @FocusState private var focus: Field?

    private enum Field { case heard, written }

    init(heard: String, written: String, model: SettingsModel) {
        self.heard = heard
        self.written = written
        self.model = model
        _wrong = State(initialValue: heard)
        _right = State(initialValue: written)
    }

    var body: some View {
        HStack {
            TextField("heard", text: $wrong).focused($focus, equals: .heard).onSubmit(save)
            Text("→").foregroundStyle(.secondary)
            TextField("written", text: $right).focused($focus, equals: .written).onSubmit(save)
            Button { model.changeDictionary { $0.replace[heard] = nil } } label: { Image(systemName: "minus") }.help("Remove this rule")
        }
        .labelsHidden()
        .textFieldStyle(.roundedBorder)
        .onChange(of: focus) { if focus == nil { save() } }
    }

    /// A row whose rule was changed already (saved, or edited by hand) does nothing: it is about to be replaced.
    private func save() {
        guard wrong != heard || right != written, model.dictionary.replace[heard] == written else { return }
        model.changeDictionary { try $0.setRule(heard: wrong, written: right, replacing: heard) }
        if model.lastError != nil {
            wrong = heard
            right = written
        }
    }
}

/// The empty last row: Enter in "heard" goes on to "written"; Enter there or + adds the rule.
private struct NewRuleRow: View {
    let model: SettingsModel
    @State private var wrong = ""
    @State private var right = ""
    @FocusState private var writtenFocused: Bool

    var body: some View {
        HStack {
            TextField("heard", text: $wrong, prompt: Text("heard")).onSubmit { writtenFocused = true }
            Text("→").foregroundStyle(.secondary)
            TextField("written", text: $right, prompt: Text("written")).focused($writtenFocused).onSubmit(add)
            Button(action: add) { Image(systemName: "plus") }.help("Add this rule")
        }
        .labelsHidden()
        .textFieldStyle(.roundedBorder)
    }

    private func add() {
        model.changeDictionary { try $0.setRule(heard: wrong, written: right) }
        if model.lastError == nil {
            wrong = ""
            right = ""
        }
    }
}

/// Chips in rows that wrap.
private struct Flow: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        let frames = frames(width, subviews)
        return CGSize(width: width.isFinite ? width : frames.map(\.maxX).max() ?? 0, height: frames.map(\.maxY).max() ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (view, frame) in zip(subviews, frames(bounds.width, subviews)) {
            view.place(at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY), proposal: ProposedViewSize(frame.size))
        }
    }

    /// Left to right, a new row when the next chip does not fit; a chip wider than the row is cut to it.
    private func frames(_ width: CGFloat, _ subviews: Subviews) -> [CGRect] {
        var frames: [CGRect] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var row: CGFloat = 0
        for view in subviews {
            var size = view.sizeThatFits(.unspecified)
            size.width = min(size.width, width)
            if x > 0, x + size.width > width {
                x = 0
                y += row + spacing
                row = 0
            }
            frames.append(CGRect(origin: CGPoint(x: x, y: y), size: size))
            x += size.width + spacing
            row = max(row, size.height)
        }
        return frames
    }
}
