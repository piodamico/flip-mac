//
//  FlipMacApp.swift
//  FlipMac
//
//  Created by Antonio Pio D’Amico on 20/11/2026.
//

import SwiftUI

@main
struct FlipMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    // Nessuna finestra: l'interfaccia è solo il menu nella menu bar (LSUIElement).
    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}
