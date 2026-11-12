import AppKit
import Foundation
import ServiceManagement

// No top-level `await` here: it would run this whole file as an async job on the main queue, and
// the app's run loop could then never drain the main queue — every @MainActor Task would hang.
let arguments = Array(CommandLine.arguments.dropFirst())

/// Runs a CLI subcommand on the main actor and exits with its status.
func runCommand(_ body: @escaping @MainActor () async -> Int32) -> Never {
    Task { @MainActor in exit(await body()) }
    dispatchMain()
}

switch arguments.first {
case "bench":
    runCommand { await Bench.run(arguments: Array(arguments.dropFirst())) }
case "apple-assets":
    guard #available(macOS 26, *) else {
        print("Apple Speech requires macOS 26 or later")
        exit(1)
    }
    runCommand { await AppleAssets.run(arguments: Array(arguments.dropFirst())) }
case "tap-test":
    runCommand { await TapTest.run(arguments: Array(arguments.dropFirst())) }
case "capture-test":
    runCommand { await CaptureTest.run(arguments: Array(arguments.dropFirst())) }
case "call-watch":
    CallWatchTest.run()
case "login-item":
    // `Shepit login-item on|off` — for scripts/uninstall.sh: only the app itself can change its login item.
    let on = arguments.dropFirst().first == "on"
    do {
        if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        exit(0)
    } catch {
        FileHandle.standardError.write(Data("login item: \(error.localizedDescription)\n".utf8))
        exit(1)
    }
default:
    let application = NSApplication.shared
    let delegate = AppDelegate()
    application.delegate = delegate
    application.run()
}
