//
//  AppDelegate.swift
//  FlipMac
//

import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let logger = FileLogger.shared
    private lazy var monitor = DragMonitor(logger: logger)
    private var statusItem: NSStatusItem?
    private var permissionPolling: Task<Void, Never>?
    private var loggedStartFailure = false
    private var didShutDown = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        logger.log("APP_START")
        logPermissions()
        setUpStatusItem()

        if !Permissions.allGranted, Permissions.explainMissing() {
            Permissions.requestMissing()
        }
        startMonitorIfPossible()
        startPermissionPolling()
    }

    func applicationWillTerminate(_ notification: Notification) {
        shutDown()
    }

    /// Rimuove il listener e chiude il log, una sola volta: LISTENER_STOP compare sempre prima di APP_QUIT.
    private func shutDown() {
        guard !didShutDown else { return }
        didShutDown = true
        permissionPolling?.cancel()
        if monitor.isRunning {
            monitor.stop()
        } else {
            logger.log("LISTENER_STOP (non era attivo)")
        }
        logger.log("APP_QUIT")
    }

    // MARK: - Menu bar

    private func setUpStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "arrow.down.circle", accessibilityDescription: "FlipMac")
        item.button?.image?.isTemplate = true

        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false
        item.menu = menu
        statusItem = item
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        menu.addItem(disabledItem("FlipMac · prototipo hook"))
        menu.addItem(disabledItem("Listener: \(monitor.isRunning ? "attivo" : "non attivo")"))
        menu.addItem(disabledItem("Accessibilità: \(status(Permissions.isAccessibilityGranted))"))
        menu.addItem(disabledItem("Input Monitoring: \(status(Permissions.isInputMonitoringGranted))"))
        menu.addItem(.separator())

        if !Permissions.allGranted {
            menu.addItem(actionItem("Richiedi permessi…", #selector(requestPermissions)))
        }
        menu.addItem(actionItem("Apri impostazioni Accessibilità", #selector(openAccessibilitySettings)))
        menu.addItem(actionItem("Apri impostazioni Input Monitoring", #selector(openInputMonitoringSettings)))
        menu.addItem(actionItem("Mostra log nel Finder", #selector(revealLog)))
        menu.addItem(.separator())
        menu.addItem(actionItem("Esci da FlipMac", #selector(quit), key: "q"))
    }

    private func disabledItem(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func actionItem(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    private func status(_ granted: Bool) -> String {
        granted ? "✓ concesso" : "✗ non concesso"
    }

    @objc private func requestPermissions() {
        if Permissions.explainMissing() {
            Permissions.requestMissing()
        }
    }

    @objc private func openAccessibilitySettings() {
        Permissions.openAccessibilitySettings()
    }

    @objc private func openInputMonitoringSettings() {
        Permissions.openInputMonitoringSettings()
    }

    @objc private func revealLog() {
        NSWorkspace.shared.activateFileViewerSelecting([logger.fileURL])
    }

    @objc private func quit() {
        // Rimozione esplicita del listener prima di uscire.
        shutDown()
        NSApp.terminate(nil)
    }

    // MARK: - Permessi e listener

    private func logPermissions() {
        logger.log(
            "PERMISSIONS accessibilita=\(Permissions.isAccessibilityGranted ? "sì" : "no") inputMonitoring=\(Permissions.isInputMonitoringGranted ? "sì" : "no")"
        )
    }

    /// Il tap in sola osservazione richiede Input Monitoring; senza, macOS rifiuta di crearlo.
    private func startMonitorIfPossible() {
        guard !monitor.isRunning, Permissions.isInputMonitoringGranted else { return }
        if monitor.start() {
            loggedStartFailure = false
        } else if !loggedStartFailure {
            loggedStartFailure = true
            logger.log("LISTENER_START_FAILED (riprovo ogni 2 secondi; se persiste, esci e riapri FlipMac)")
        }
    }

    /// Ricontrolla i permessi ogni 2 secondi finché non sono tutti concessi e il listener è attivo.
    private func startPermissionPolling() {
        var lastAccessibility = Permissions.isAccessibilityGranted
        var lastInputMonitoring = Permissions.isInputMonitoringGranted

        permissionPolling = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard let self, !Task.isCancelled else { return }

                let accessibility = Permissions.isAccessibilityGranted
                let inputMonitoring = Permissions.isInputMonitoringGranted
                if accessibility != lastAccessibility || inputMonitoring != lastInputMonitoring {
                    lastAccessibility = accessibility
                    lastInputMonitoring = inputMonitoring
                    self.logPermissions()
                }

                self.startMonitorIfPossible()
                if accessibility, inputMonitoring, self.monitor.isRunning {
                    return
                }
            }
        }
    }
}
