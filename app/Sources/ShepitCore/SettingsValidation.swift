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
    let settingChecks: [(String, (Any) -> String?)] = [
        ("mode", enumCheck(["toggle", "hold"])),
        ("cancelKey", kindCheck("string")),
        ("model", enumCheck(["large-v3", "large-v3-turbo"])),
        ("language", enumCheck(["uk", "en", "auto"])),
        ("stylePrompt", kindCheck("string")),
        ("refocusOriginalApp", kindCheck("boolean")),

        ("restoreClipboard", kindCheck("boolean")),
        ("sounds", kindCheck("boolean")),
        ("maxRecordingSeconds", integerCheck(5, 3600)),
        ("idleUnloadMinutes", integerCheck(0, 1440)),
        ("overlay", kindCheck("boolean")),
        ("livePreview", kindCheck("boolean")),
        ("previewModel", enumCheck(["large-v3", "large-v3-turbo"])),
        ("historyMenuItems", integerCheck(0, 50)),
        ("microphone", kindCheck("string")),
        ("saveHistory", kindCheck("boolean")),
        ("historyDays", integerCheck(0, 3650)),
        ("failedAudioHours", integerCheck(0, 720)),
        ("launchAtLogin", kindCheck("boolean")),
        ("typingSpeedWpm", integerCheck(10, 200)),
        ("collectStats", kindCheck("boolean")),
        ("meetingsFolder", folderCheck),
        ("meetingFileName", { value in
            guard let template = value as? String else { return "must be a string" }
            return MeetingFileName.validate(template)
        }),
        ("meetingAskTitle", kindCheck("boolean")),
        ("meetingBlocksDictation", kindCheck("boolean")),
        ("meetingMyName", kindCheck("string")),
        ("meetingLanguage", enumCheck(["uk", "en", "auto"])),
        ("callOffer", kindCheck("boolean")),
        ("callOfferSeconds", { value in
            guard let seconds = integerValue(value), seconds == 0 || (5...120).contains(seconds) else {
                return "must be 0 or a whole number from 5 to 120"
            }
            return nil
        }),
        ("callAutoStart", kindCheck("boolean")),
        ("callAutoStartSeconds", integerCheck(3, 60)),
        ("callAutoStopSeconds", integerCheck(3, 120)),
        ("callApps", { value in
            guard let apps = value as? [String], Set(apps).count == apps.count,
                  apps.allSatisfy(Settings.callAppNames.contains) else {
                return "must be a list of: \(Settings.callAppNames.joined(separator: ", ")), each at most once"
            }
            return nil
        })
    ]

    for (key, check) in settingChecks {
        if (key == "model" && engineValuesForPrecedence[EngineTask.dictation.rawValue] != nil)
            || (key == "previewModel" && engineValuesForPrecedence[EngineTask.preview.rawValue] != nil) { continue }
        guard let value = raw[key] else { continue }
        if let problem = check(value) {
            errors.append("settings.json: \"\(key)\" \(problem)")
            continue
        }
        assign(value, to: key, settings: &settings)
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

    if let rawStyle = raw["overlayStyle"] {
        guard let styleValues = rawStyle as? [String: Any], isJSONObject(styleValues) else {
            errors.append(#"settings.json: "overlayStyle" must be an object"#)
            return (nil, errors.sorted())
        }
        for key in OverlayStyleKeys.all {
            guard let value = styleValues[key] else { continue }
            if let problem = validateOverlayValue(value, key: key) {
                errors.append("settings.json: \"overlayStyle.\(key)\" \(problem)")
            } else {
                assignOverlay(value, key: key, style: &settings.overlayStyle)
            }
        }
    }

    if let rawEngines = raw["engines"] {
        guard let engineValues = rawEngines as? [String: Any], isJSONObject(engineValues) else {
            errors.append(#"settings.json: "engines" must be an object"#)
            return (nil, errors.sorted())
        }
        let allowedTasks = EngineTask.allCases.map(\.rawValue)
        for taskName in engineValues.keys.sorted() where !allowedTasks.contains(taskName) {
            errors.append("settings.json: \"engines\" has unknown task \"\(taskName)\"; allowed: \(allowedTasks.joined(separator: ", "))")
        }
        for task in EngineTask.allCases {
            if let explicit = engineValues[task.rawValue] {
                if let choice = validateEngineChoice(explicit, task: task, catalog: catalog, errors: &errors) {
                    settings.engines[task] = choice
                }
            } else {
                if task == .dictation, raw["model"] != nil {
                    settings.engines[task] = EngineChoice(engine: .whispercpp, model: settings.model)
                } else if task == .preview, raw["previewModel"] != nil {
                    settings.engines[task] = EngineChoice(engine: .whispercpp, model: settings.previewModel)
                }
            }
        }
    } else {
        if raw["model"] != nil {
            settings.engines[.dictation] = EngineChoice(engine: .whispercpp, model: settings.model)
        }
        if raw["previewModel"] != nil {
            settings.engines[.preview] = EngineChoice(engine: .whispercpp, model: settings.previewModel)
        }
    }

    return errors.isEmpty ? (settings, []) : (nil, errors.sorted())
}

private enum OverlayStyleKeys {
    static let all = [
        "position", "width", "opacity", "backgroundColor", "textColor", "fontSize",
        "listeningText", "transcribingText", "doneText", "showTimer", "showMeter",
        "meterColor", "bars", "doneSeconds", "messageSeconds"
    ]
}

private func validateOverlayValue(_ value: Any, key: String) -> String? {
    switch key {
    case "position": return enumCheck(["bottom", "top", "center"])(value)
    case "width": return integerCheck(360, 1600)(value)
    case "opacity": return numberCheck(0.2, 1)(value)
    case "backgroundColor", "textColor", "meterColor":
        guard let color = value as? String,
              color.range(of: #"^#(?:[0-9A-Fa-f]{6}|[0-9A-Fa-f]{8})$"#, options: .regularExpression) != nil else {
            return ##"must be a color like "#FF4D4D" (or "#RRGGBBAA")"##
        }
        return nil
    case "fontSize": return integerCheck(10, 28)(value)
    case "listeningText", "transcribingText", "doneText": return kindCheck("string")(value)
    case "showTimer", "showMeter": return kindCheck("boolean")(value)
    case "bars": return integerCheck(3, 24)(value)
    case "doneSeconds": return numberCheck(0, 10)(value)
    case "messageSeconds": return numberCheck(0.5, 10)(value)
    default: return nil
    }
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

private func enumCheck(_ values: [String]) -> (Any) -> String? {
    { value in
        guard let string = value as? String, values.contains(string) else {
            return "must be one of: \(values.joined(separator: ", "))"
        }
        return nil
    }
}

private func folderCheck(_ value: Any) -> String? {
    guard let path = value as? String, path.hasPrefix("/") || (path.hasPrefix("~/") && path.count > 2) else {
        return "must be an absolute path or start with ~/"
    }
    return nil
}

private func kindCheck(_ expected: String) -> (Any) -> String? {
    { value in
        switch expected {
        case "boolean": return isBoolean(value) ? nil : "must be a boolean"
        case "string": return value is String ? nil : "must be a string"
        default: return nil
        }
    }
}

private func integerCheck(_ min: Int, _ max: Int) -> (Any) -> String? {
    { value in
        guard let integer = integerValue(value), (min...max).contains(integer) else {
            return "must be a whole number from \(min) to \(max)"
        }
        return nil
    }
}

private func numberCheck(_ min: Double, _ max: Double) -> (Any) -> String? {
    { value in
        guard !isBoolean(value), let number = value as? NSNumber,
              number.doubleValue >= min, number.doubleValue <= max else {
            return "must be a number from \(decimalString(min)) to \(decimalString(max))"
        }
        return nil
    }
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

private func assign(_ value: Any, to key: String, settings: inout Settings) {
    switch key {
    case "mode": settings.mode = value as! String
    case "cancelKey": settings.cancelKey = value as! String
    case "model": settings.model = value as! String
    case "language": settings.language = value as! String
    case "stylePrompt": settings.stylePrompt = value as! String
    case "refocusOriginalApp": settings.refocusOriginalApp = value as! Bool
    case "restoreClipboard": settings.restoreClipboard = value as! Bool
    case "sounds": settings.sounds = value as! Bool
    case "maxRecordingSeconds": settings.maxRecordingSeconds = integerValue(value)!
    case "idleUnloadMinutes": settings.idleUnloadMinutes = integerValue(value)!
    case "overlay": settings.overlay = value as! Bool
    case "livePreview": settings.livePreview = value as! Bool
    case "previewModel": settings.previewModel = value as! String
    case "historyMenuItems": settings.historyMenuItems = integerValue(value)!
    case "microphone": settings.microphone = value as! String
    case "saveHistory": settings.saveHistory = value as! Bool
    case "historyDays": settings.historyDays = integerValue(value)!
    case "failedAudioHours": settings.failedAudioHours = integerValue(value)!
    case "launchAtLogin": settings.launchAtLogin = value as! Bool
    case "typingSpeedWpm": settings.typingSpeedWpm = integerValue(value)!
    case "collectStats": settings.collectStats = value as! Bool
    case "meetingsFolder": settings.meetingsFolder = value as! String
    case "meetingFileName": settings.meetingFileName = value as! String
    case "meetingAskTitle": settings.meetingAskTitle = value as! Bool
    case "meetingBlocksDictation": settings.meetingBlocksDictation = value as! Bool
    case "meetingMyName": settings.meetingMyName = value as! String
    case "meetingLanguage": settings.meetingLanguage = value as! String
    case "callOffer": settings.callOffer = value as! Bool
    case "callOfferSeconds": settings.callOfferSeconds = integerValue(value)!
    case "callAutoStart": settings.callAutoStart = value as! Bool
    case "callAutoStartSeconds": settings.callAutoStartSeconds = integerValue(value)!
    case "callAutoStopSeconds": settings.callAutoStopSeconds = integerValue(value)!
    case "callApps": settings.callApps = value as! [String]
    default: break
    }
}

private func assignOverlay(_ value: Any, key: String, style: inout OverlayStyle) {
    switch key {
    case "position": style.position = value as! String
    case "width": style.width = integerValue(value)!
    case "opacity": style.opacity = (value as! NSNumber).doubleValue
    case "backgroundColor": style.backgroundColor = value as! String
    case "textColor": style.textColor = value as! String
    case "fontSize": style.fontSize = integerValue(value)!
    case "listeningText": style.listeningText = value as! String
    case "transcribingText": style.transcribingText = value as! String
    case "doneText": style.doneText = value as! String
    case "showTimer": style.showTimer = value as! Bool
    case "showMeter": style.showMeter = value as! Bool
    case "meterColor": style.meterColor = value as! String
    case "bars": style.bars = integerValue(value)!
    case "doneSeconds": style.doneSeconds = (value as! NSNumber).doubleValue
    case "messageSeconds": style.messageSeconds = (value as! NSNumber).doubleValue
    default: break
    }
}
