import AppKit
import AVFoundation
import ApplicationServices

@MainActor
enum Permissions {
    static var accessibilityGranted: Bool {
        AXIsProcessTrusted()
    }

    static var microphoneGranted: Bool {
        AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }

    static var microphoneDenied: Bool {
        AVCaptureDevice.authorizationStatus(for: .audio) == .denied
            || AVCaptureDevice.authorizationStatus(for: .audio) == .restricted
    }

    static func requestAccessibility() {
        let prompt = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(prompt)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    static func requestMicrophone() {
        if microphoneDenied {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
                NSWorkspace.shared.open(url)
            }
        } else {
            AVCaptureDevice.requestAccess(for: .audio) { _ in }
        }
    }
}
