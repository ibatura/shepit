import SwiftUI
import ShepitCore

/// The window's Dictionary section: dictionary.json's terms, replace rules and dropped phrases.
struct DictionarySection: View {
    let model: SettingsModel
    @State private var newTerm = ""
    @State private var wrong = ""
    @State private var right = ""
    @State private var editing: String?
    @State private var newPhrase = ""

    var body: some View {
        Section {
            List {
                ForEach(model.dictionary.terms, id: \.self) { term in
                    HStack {
                        Text(term)
                        Spacer()
                        Button(role: .destructive) { model.setTerms(model.dictionary.terms.filter { $0 != term }) } label: { Image(systemName: "minus.circle") }
                            .buttonStyle(.borderless)
                    }
                }
                .onMove { from, to in
                    var terms = model.dictionary.terms
                    terms.move(fromOffsets: from, toOffset: to)
                    model.setTerms(terms)
                }
            }
            .frame(minHeight: 120)
            HStack {
                TextField("New term", text: $newTerm).onSubmit(addTerm)
                Button("Add", action: addTerm).disabled(newTerm.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        } header: {
            Text("Terms")
        } footer: {
            Text("""
                Before recognition: a hint. The engine reads these words with the style prompt and tries to spell them \
                this way, in any form (Kubernetes, Kubernetes-кластер). Not guaranteed, and only engines that take a prompt \
                use it (whisper.cpp, WhisperKit; not Parakeet). Only about 200 tokens are read, so drag the most important first.
                """)
                .font(.caption).foregroundStyle(.secondary)
        }
        Section {
            ForEach(model.dictionary.replace.sorted { $0.key < $1.key }, id: \.key) { rule in
                HStack {
                    Text(rule.key)
                    Image(systemName: "arrow.right").foregroundStyle(.secondary)
                    Text(rule.value)
                    Spacer()
                    Button("Edit") { editing = rule.key; wrong = rule.key; right = rule.value }.buttonStyle(.borderless)
                    Button(role: .destructive) { model.removeRule(rule.key) } label: { Image(systemName: "minus.circle") }
                        .buttonStyle(.borderless)
                }
            }
            HStack {
                TextField("What was heard", text: $wrong)
                Image(systemName: "arrow.right").foregroundStyle(.secondary)
                TextField("Correct spelling", text: $right).onSubmit(saveRule)
                Button(editing == nil ? "Add" : "Save", action: saveRule)
                if editing != nil { Button("Cancel") { editing = nil; wrong = ""; right = "" } }
            }
        } header: {
            Text("Replace")
        } footer: {
            Text("""
                After recognition: a guaranteed fix. When the text contains exactly what was heard, it's replaced with the \
                correct spelling, with any engine. Each wrong variant needs its own rule (кубернетес, кубернетис…). \
                Ignores upper/lower case, matches whole words only, longer phrases win. Use it for what Terms didn't fix; \
                ⌃⌥D on a selected word adds both a rule and a term.
                """)
                .font(.caption).foregroundStyle(.secondary)
        }
        Section {
            ForEach(model.dictionary.dropPhrases, id: \.self) { phrase in
                HStack {
                    Text(phrase)
                    Spacer()
                    Button(role: .destructive) { model.setDropPhrases(model.dictionary.dropPhrases.filter { $0 != phrase }) } label: { Image(systemName: "minus.circle") }
                        .buttonStyle(.borderless)
                }
            }
            HStack {
                TextField("Phrase", text: $newPhrase).onSubmit(addPhrase)
                Button("Add", action: addPhrase).disabled(newPhrase.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        } header: {
            Text("Drop phrases")
        } footer: {
            Text("Phrases the engine invents on silence or at the end, removed when they're the last sentence. Common ones («Дякую за перегляд!», “Thanks for watching”) are built in.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func addTerm() {
        let term = newTerm.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty, !model.dictionary.terms.contains(term) else { return }
        model.setTerms(model.dictionary.terms + [term])
        newTerm = ""
    }

    private func saveRule() {
        model.setRule(wrong: wrong, right: right, replacing: editing)
        if model.lastError == nil {
            editing = nil
            wrong = ""
            right = ""
        }
    }

    private func addPhrase() {
        let phrase = newPhrase.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !phrase.isEmpty, !model.dictionary.dropPhrases.contains(phrase) else { return }
        model.setDropPhrases(model.dictionary.dropPhrases + [phrase])
        newPhrase = ""
    }
}
