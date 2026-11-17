import Foundation

/// People's names compared as one (voices design §5): the same ignoring case, accents and script.
public enum Names {
    /// A name in Latin letters, lower case, without accents: "Олена", "Oléna" and "olena" are the same.
    public static func fold(_ text: String) -> String {
        (text.applyingTransform(.toLatin, reverse: false) ?? text).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }

    /// What a person is found by: the folded name; nil for a label that names nobody (empty, "Person 3", the live label).
    public static func key(_ name: String) -> String? {
        let name = name.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, name != MeetingNote.callLabel, name.wholeMatch(of: /Person \d+/) == nil else { return nil }
        return fold(name)
    }
}
