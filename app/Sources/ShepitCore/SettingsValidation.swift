import CoreFoundation
import Foundation

public func validateSettings(
    _ raw: [String: Any],
    catalog: ModelCatalog.Type = ModelCatalog.self
) -> (Settings?, [String]) {
    guard isJSONObject(raw) else {
        return (nil, ["settings.json: must be a JSON object"])
    }

    var settings = Settings.defaults
    var errors: [String] = []
    let engineValuesForPrecedence = raw["engines"] as? [String: Any] ?? [:]

    for (key, field) in settingFields {
        if (key == "model" && engineValuesForPrecedence[EngineTask.dictation.rawValue] != nil)
            || (key == "previewModel" && engineValuesForPrecedence[EngineTask.preview.rawValue] != nil) { continue }
        guard let value = raw[key] else { continue }
        if let problem = field(value, &settings) { errors.append("settings.json: \"\(key)\" \(problem)") }
    }

    if let value = raw["hotkey"] {
        if let hotkey = validateHotkey(value, key: "hotkey", errors: &errors) {
            settings.hotkey = hotkey
        }
    }
    if let value = raw["addWordHotkey"] {
        if let hotkey = validateHotkey(value, key: "addWordHotkey", errors: &errors) {
            settings.addWordHotkey = hotkey
        }
    }

    // null means no shortcut, the same as leaving the key out.
    if let value = raw["meetingHotkey"], !(value is NSNull) {
        settings.meetingHotkey = validateHotkey(value, key: "meetingHotkey", errors: &errors)
    }

    if let rawStyle = raw["overlayStyle"] {
        guard let styleValues = rawStyle as? [String: Any], isJSONObject(styleValues) else {
            errors.append(#"settings.json: "overlayStyle" must be an object"#)
            return (nil, errors.sorted())
        }
        for (key, field) in overlayFields {
            guard let value = styleValues[key] else { continue }
            if let problem = field(value, &settings.overlayStyle) { errors.append("settings.json: \"overlayStyle.\(key)\" \(problem)") }
        }
    }

    var engineValues: [String: Any] = [:]
    if let rawEngines = raw["engines"] {
        guard let values = rawEngines as? [String: Any], isJSONObject(values) else {
            errors.append(#"settings.json: "engines" must be an object"#)
            return (nil, errors.sorted())
        }
        engineValues = values
        let allowedTasks = EngineTask.allCases.map(\.rawValue)
        for taskName in engineValues.keys.sorted() where !allowedTasks.contains(taskName) {
            errors.append("settings.json: \"engines\" has unknown task \"\(taskName)\"; allowed: \(allowedTasks.joined(separator: ", "))")
        }
    }
    // An old file: `model` and `previewModel` fill in the engines `engines` doesn't name (README).
    let oldModelKeys: [EngineTask: String] = [.dictation: "model", .preview: "previewModel"]
    for task in EngineTask.allCases {
        if let explicit = engineValues[task.rawValue] {
            if let choice = validateEngineChoice(explicit, task: task, catalog: catalog, errors: &errors) {
                settings.engines[task] = choice
            }
        } else if let model = oldModelKeys[task].flatMap({ raw[$0] as? String }) {
            settings.engines[task] = EngineChoice(engine: .whispercpp, model: model)
        }
    }
    // An old file without `callModes`: each app's choice from `callApps`, `callOffer` and `callAutoStart`, as the offer read
    // them (settings review design §7.2).
    if raw["callModes"] == nil {
        let apps = raw["callApps"] as? [String] ?? Settings.callAppNames
        let offer = raw["callOffer"] as? Bool ?? true, auto = raw["callAutoStart"] as? Bool ?? false
        settings.callModes = Dictionary(uniqueKeysWithValues: CallApp.allCases.map { app in
            (app, apps.contains(app.rawValue) && offer ? (auto ? CallMode.auto : .offer) : .off)
        })
    }

    return errors.isEmpty ? (settings, []) : (nil, errors.sorted())
}

/// A key of the file: reads its value into the settings, or says what is wrong with it ("must be …").
private typealias Field<Root> = @Sendable (Any, inout Root) -> String?

/// The plain keys; `hotkey`, `addWordHotkey`, `meetingHotkey`, `overlayStyle` and `engines` are read apart. The keys of an
/// old file are only checked here, and read at the end into `engines` and `callModes`.
private let settingFields: [(String, Field<Settings>)] = [
    ("mode", oneOf(\.mode, Settings.modes.map(\.value))),
    ("cancelKey", string(\.cancelKey)),
    ("model", checked(oldModelProblem) { ($0 as? String).flatMap { oldModels.contains($0) ? $0 : nil } }),
    ("language", oneOf(\.language, Settings.languages.map(\.value))),
    ("stylePrompt", string(\.stylePrompt)),
    ("refocusOriginalApp", boolean(\.refocusOriginalApp)),
    ("restoreClipboard", boolean(\.restoreClipboard)),
    ("sounds", boolean(\.sounds)),
    ("maxRecordingSeconds", integer(\.maxRecordingSeconds, 5...3600)),
    ("idleUnloadMinutes", integer(\.idleUnloadMinutes, 0...1440)),
    ("overlay", boolean(\.overlay)),
    ("livePreview", boolean(\.livePreview)),
    ("previewModel", checked(oldModelProblem) { ($0 as? String).flatMap { oldModels.contains($0) ? $0 : nil } }),
    ("historyMenuItems", integer(\.historyMenuItems, 0...50)),
    ("microphone", string(\.microphone)),
    ("saveHistory", boolean(\.saveHistory)),
    ("historyDays", integer(\.historyDays, 0...3650)),
    ("failedAudioHours", integer(\.failedAudioHours, 0...720)),
    ("launchAtLogin", boolean(\.launchAtLogin)),
    ("typingSpeedWpm", integer(\.typingSpeedWpm, 10...200)),
    ("collectStats", boolean(\.collectStats)),
    ("databasesFolder", folder(\.databasesFolder)),
    ("meetingsFolder", folder(\.meetingsFolder)),
    ("meetingFileName", { value, settings in
        guard let template = value as? String else { return "must be a string" }
        if let problem = MeetingFileName.validate(template) { return problem }
        settings.meetingFileName = template
        return nil
    }),
    ("meetingAskTitle", boolean(\.meetingAskTitle)),
    ("meetingBlocksDictation", boolean(\.meetingBlocksDictation)),
    ("meetingMyName", string(\.meetingMyName)),
    ("meetingLanguage", oneOf(\.meetingLanguage, Settings.languages.map(\.value))),
    ("callOffer", checked("must be a boolean") { isBoolean($0) ? $0 : nil }),
    ("callOfferSeconds", field(\.callOfferSeconds, "must be 0 or a whole number from 5 to 120") {
        integerValue($0).flatMap { $0 == 0 || (5...120).contains($0) ? $0 : nil }
    }),
    ("callAutoStart", checked("must be a boolean") { isBoolean($0) ? $0 : nil }),
    ("callAutoStartSeconds", integer(\.callAutoStartSeconds, 3...60)),
    ("callAutoStopSeconds", integer(\.callAutoStopSeconds, 3...120)),
    ("callApps", checked("must be a list of: \(Settings.callAppNames.joined(separator: ", ")), each at most once") {
        ($0 as? [String]).flatMap { Set($0).count == $0.count && $0.allSatisfy(Settings.callAppNames.contains) ? $0 : nil }
    }),
    ("callModes", field(\.callModes, "must be an object from an app (\(Settings.callAppNames.joined(separator: ", "))) to auto, offer or off") {
        Settings.callModes(file: $0)
    }),
    ("callRules", field(\.callRules, "must be a list of rules, each with app (\(Settings.callAppNames.joined(separator: ", "))), match (contains, is), text and then (auto, offer, off)") {
        Settings.callRules(file: $0)
    }),
    ("theme", oneOf(\.theme, Settings.themes.map(\.value))),
    ("accentColor", field(\.accentColor, "must be one of: \(AccentColor.allCases.map(\.rawValue).joined(separator: ", "))") {
        ($0 as? String).flatMap(AccentColor.init(rawValue:))
    }),
    ("rememberVoices", boolean(\.rememberVoices)),
]

/// The models `model` and `previewModel` could name: whisper.cpp's.
private let oldModels = ["large-v3", "large-v3-turbo"]
private let oldModelProblem = "must be one of: \(oldModels.joined(separator: ", "))"

private let overlayFields: [(String, Field<OverlayStyle>)] = [
    ("position", oneOf(\.position, ["bottom", "top", "center"])),
    ("width", integer(\.width, 360...1600)),
    ("opacity", number(\.opacity, 0.2...1)),
    ("backgroundColor", color(\.backgroundColor)),
    ("textColor", color(\.textColor)),
    ("fontSize", integer(\.fontSize, 10...28)),
    ("listeningText", string(\.listeningText)),
    ("transcribingText", string(\.transcribingText)),
    ("doneText", string(\.doneText)),
    ("showTimer", boolean(\.showTimer)),
    ("showMeter", boolean(\.showMeter)),
    ("meterColor", color(\.meterColor)),
    ("bars", integer(\.bars, 3...24)),
    ("doneSeconds", number(\.doneSeconds, 0...10)),
    ("messageSeconds", number(\.messageSeconds, 0.5...10)),
]

/// A value `read` accepts goes to `path`; anything else is `problem`.
private func field<Root, Value>(_ path: WritableKeyPath<Root, Value> & Sendable, _ problem: String,
                                _ read: @escaping @Sendable (Any) -> Value?) -> Field<Root> {
    { value, root in
        guard let read = read(value) else { return problem }
        root[keyPath: path] = read
        return nil
    }
}

/// A key of an old file: checked, and read later into the key that replaced it.
private func checked<Root, Value>(_ problem: String, _ read: @escaping @Sendable (Any) -> Value?) -> Field<Root> {
    { value, _ in read(value) == nil ? problem : nil }
}

private func string<Root>(_ path: WritableKeyPath<Root, String> & Sendable) -> Field<Root> {
    field(path, "must be a string") { $0 as? String }
}

private func boolean<Root>(_ path: WritableKeyPath<Root, Bool> & Sendable) -> Field<Root> {
    field(path, "must be a boolean") { isBoolean($0) ? $0 as? Bool : nil }
}

private func integer<Root>(_ path: WritableKeyPath<Root, Int> & Sendable, _ range: ClosedRange<Int>) -> Field<Root> {
    field(path, "must be a whole number from \(range.lowerBound) to \(range.upperBound)") { integerValue($0).flatMap { range.contains($0) ? $0 : nil } }
}

private func number<Root>(_ path: WritableKeyPath<Root, Double> & Sendable, _ range: ClosedRange<Double>) -> Field<Root> {
    field(path, "must be a number from \(decimalString(range.lowerBound)) to \(decimalString(range.upperBound))") {
        guard !isBoolean($0), let number = ($0 as? NSNumber)?.doubleValue, range.contains(number) else { return nil }
        return number
    }
}

private func oneOf<Root>(_ path: WritableKeyPath<Root, String> & Sendable, _ values: [String]) -> Field<Root> {
    field(path, "must be one of: \(values.joined(separator: ", "))") { ($0 as? String).flatMap { values.contains($0) ? $0 : nil } }
}

private func color<Root>(_ path: WritableKeyPath<Root, String> & Sendable) -> Field<Root> {
    field(path, ##"must be a color like "#FF4D4D" (or "#RRGGBBAA")"##) {
        ($0 as? String).flatMap { $0.range(of: #"^#(?:[0-9A-Fa-f]{6}|[0-9A-Fa-f]{8})$"#, options: .regularExpression) != nil ? $0 : nil }
    }
}

private func folder<Root>(_ path: WritableKeyPath<Root, String> & Sendable) -> Field<Root> {
    field(path, "must be an absolute path or start with ~/") {
        ($0 as? String).flatMap { $0.hasPrefix("/") || ($0.hasPrefix("~/") && $0.count > 2) ? $0 : nil }
    }
}

extension Settings {
    /// Every key settings.json may have. `model` and `previewModel` only fill in `engines` for an old file.
    public static let fileKeys = settingFields.map(\.0) + ["hotkey", "addWordHotkey", "meetingHotkey", "overlayStyle", "engines"]
}

private func validateHotkey(_ value: Any, key: String, errors: inout [String]) -> Hotkey? {
    guard let object = value as? [String: Any], isJSONObject(object) else {
        errors.append("settings.json: \"\(key)\" must be an object like {\"mods\": [\"alt\"], \"key\": \"space\"}")
        return nil
    }

    var valid = true
    let mods = object["mods"] ?? [String]()
    guard let values = mods as? [Any], !isJSONObject(mods), values.allSatisfy({ $0 is String }) else {
        errors.append("settings.json: \"\(key).mods\" must be a list of: cmd, alt, ctrl, shift")
        valid = false
        let values = [String]()
        return validateHotkeyKey(object, key: key, mods: values, valid: valid, errors: &errors)
    }
    let stringMods = values as! [String]
    if stringMods.contains(where: { !["cmd", "alt", "ctrl", "shift"].contains($0) }) {
        errors.append("settings.json: \"\(key).mods\" must be a list of: cmd, alt, ctrl, shift")
        valid = false
    }
    return validateHotkeyKey(object, key: key, mods: valid ? stringMods : [], valid: valid, errors: &errors)
}

private func validateHotkeyKey(_ object: [String: Any], key: String, mods: [String], valid: Bool, errors: inout [String]) -> Hotkey? {
    guard let hotkey = object["key"] as? String, !hotkey.isEmpty else {
        errors.append("settings.json: \"\(key).key\" must be a key name like \"space\" or \"d\"")
        return nil
    }
    return valid ? Hotkey(mods: mods, key: hotkey) : nil
}

private func validateEngineChoice(
    _ value: Any,
    task: EngineTask,
    catalog: ModelCatalog.Type,
    errors: inout [String]
) -> EngineChoice? {
    let key = "engines.\(task.rawValue)"
    guard let object = value as? [String: Any], isJSONObject(object) else {
        errors.append("settings.json: \"\(key)\" must be an object")
        return nil
    }
    let engineName = object["engine"] as? String
    guard let engineName, let engine = EngineID(rawValue: engineName) else {
        errors.append("settings.json: \"\(key).engine\" must be one of: \(EngineID.allCases.map(\.rawValue).joined(separator: ", "))")
        return nil
    }
    if let rawModel = object["model"], !(rawModel is String) {
        errors.append("settings.json: \"\(key).model\" must be one of: \(catalog.models(for: engine).joined(separator: ", "))")
        return nil
    }
    let model = object["model"] as? String ?? ""
    let allowedModels = catalog.models(for: engine)
    guard allowedModels.contains(model) else {
        errors.append("settings.json: \"\(key).model\" must be one of: \(allowedModels.joined(separator: ", "))")
        return nil
    }
    return EngineChoice(engine: engine, model: model)
}

private func decimalString(_ value: Double) -> String {
    let formatter = NumberFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.numberStyle = .decimal
    formatter.minimumFractionDigits = 0
    formatter.maximumFractionDigits = 2
    return formatter.string(from: NSNumber(value: value)) ?? String(value)
}

private func isJSONObject(_ value: Any) -> Bool {
    guard let dictionary = value as? [String: Any] else { return false }
    return JSONSerialization.isValidJSONObject(dictionary)
}

private func isBoolean(_ value: Any) -> Bool {
    guard let number = value as? NSNumber else { return false }
    return CFGetTypeID(number) == CFBooleanGetTypeID()
}

private func integerValue(_ value: Any) -> Int? {
    guard !isBoolean(value), let number = value as? NSNumber else { return nil }
    let double = number.doubleValue
    guard double.isFinite, double.rounded(.towardZero) == double,
          let integer = Int(exactly: double) else { return nil }
    return integer
}
