//
//  Permissions.swift
//  FlipMac
//

import AppKit
import ApplicationServices

/// Stato e richiesta dei permessi di sistema necessari all'hook.
enum Permissions {
    /// Accessibilità: servirà per intercettare Freccia giù durante il trascinamento (milestone della ruota).
    static var isAccessibilityGranted: Bool {
        AXIsProcessTrusted()
    }

    /// Input Monitoring: serve per osservare tastiera e mouse a livello globale con un event tap.
    static var isInputMonitoringGranted: Bool {
        CGPreflightListenEventAccess()
    }

    static var allGranted: Bool {
        isAccessibilityGranted && isInputMonitoringGranted
    }

    /// Mostra le richieste di sistema per i permessi mancanti.
    static func requestMissing() {
        if !isAccessibilityGranted {
            // "AXTrustedCheckOptionPrompt" è il valore di kAXTrustedCheckOptionPrompt.
            let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
        }
        if !isInputMonitoringGranted {
            _ = CGRequestListenEventAccess()
        }
    }

    static func openAccessibilitySettings() {
        openSettings(anchor: "Privacy_Accessibility")
    }

    static func openInputMonitoringSettings() {
        openSettings(anchor: "Privacy_ListenEvent")
    }

    private static func openSettings(anchor: String) {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") else { return }
        NSWorkspace.shared.open(url)
    }

    /// Spiega quali permessi mancano e a cosa servono. Restituisce true se l'utente vuole procedere.
    static func explainMissing() -> Bool {
        var lines: [String] = []
        if !isAccessibilityGranted {
            lines.append("• Accessibilità: servirà a FlipMac per intercettare Freccia giù mentre trascini file dal Finder. In questo prototipo il tasto viene solo osservato, mai bloccato.")
        }
        if !isInputMonitoringGranted {
            lines.append("• Input Monitoring: permette a FlipMac di accorgersi di quando trascini file e premi Freccia giù. Nel log finiscono solo i trascinamenti e Freccia giù, nessun altro tasto.")
        }

        let alert = NSAlert()
        alert.messageText = "FlipMac ha bisogno di alcuni permessi"
        alert.informativeText = lines.joined(separator: "\n\n")
            + "\n\nmacOS aprirà le richieste di sistema. Attiva FlipMac in Impostazioni di Sistema › Privacy e sicurezza. Se dopo averli concessi l'hook non parte, esci da FlipMac e riaprilo."
        alert.addButton(withTitle: "Continua")
        alert.addButton(withTitle: "Più tardi")

        NSApp.activate()
        return alert.runModal() == .alertFirstButtonReturn
    }
}
