//
//  DragMonitor.swift
//  FlipMac
//

import AppKit
import CoreGraphics

/// Evento estratto dal callback dell'event tap. Contiene solo ciò che serve al prototipo:
/// gli altri tasti vengono scartati nel callback e non arrivano mai qui.
nonisolated enum TapEvent: Sendable {
    case mouseDown(CGPoint)
    case mouseDragged(CGPoint)
    case mouseUp
    case downArrow(isRepeat: Bool)
    case tapDisabled(byTimeout: Bool)
}

/// Codice tasto virtuale di Freccia giù (kVK_DownArrow).
nonisolated private let downArrowKeyCode: Int64 = 125

/// Callback C dell'event tap. Gira sul main run loop, dove è aggiunta la sorgente del tap.
nonisolated private func dragMonitorCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    let tapEvent: TapEvent
    switch type {
    case .leftMouseDown:
        tapEvent = .mouseDown(event.location)
    case .leftMouseDragged:
        tapEvent = .mouseDragged(event.location)
    case .leftMouseUp:
        tapEvent = .mouseUp
    case .keyDown:
        // Qualsiasi tasto diverso da Freccia giù viene ignorato qui, senza leggerne o salvarne altro.
        guard event.getIntegerValueField(.keyboardEventKeycode) == downArrowKeyCode else {
            return Unmanaged.passUnretained(event)
        }
        tapEvent = .downArrow(isRepeat: event.getIntegerValueField(.keyboardEventAutorepeat) != 0)
    case .tapDisabledByTimeout:
        tapEvent = .tapDisabled(byTimeout: true)
    case .tapDisabledByUserInput:
        tapEvent = .tapDisabled(byTimeout: false)
    default:
        return Unmanaged.passUnretained(event)
    }

    if let refcon {
        let monitor = Unmanaged<DragMonitor>.fromOpaque(refcon).takeUnretainedValue()
        MainActor.assumeIsolated {
            monitor.handle(tapEvent)
        }
    }
    // Tap in sola osservazione: l'evento prosegue comunque invariato.
    return Unmanaged.passUnretained(event)
}

/// Osserva i trascinamenti di file dal Finder e la pressione di Freccia giù durante il trascinamento.
final class DragMonitor {
    private static let finderBundleIdentifier = "com.apple.finder"
    /// Spostamento minimo, in punti, prima di controllare se è iniziato un trascinamento.
    private static let dragThreshold: CGFloat = 3

    private let logger: FileLogger
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    // Stato del gesto corrente.
    private var mouseDownLocation: CGPoint?
    private var mouseDownChangeCount = 0
    private var mouseDownFrontmostApp: String?
    private var mouseDownWindowOwner: String?
    private var gestureResolved = false
    private var isDraggingFiles = false
    private var downArrowPressed = false

    var isRunning: Bool {
        tap != nil
    }

    init(logger: FileLogger) {
        self.logger = logger
    }

    /// Crea l'event tap. Restituisce false se macOS lo rifiuta (di solito per permessi mancanti).
    @discardableResult
    func start() -> Bool {
        guard tap == nil else { return true }

        let types: [CGEventType] = [.leftMouseDown, .leftMouseDragged, .leftMouseUp, .keyDown]
        let mask = types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << CGEventMask($1.rawValue)) }

        guard let newTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: dragMonitorCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            return false
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, newTap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: newTap, enable: true)

        tap = newTap
        runLoopSource = source
        resetGesture()
        logger.log("LISTENER_START")
        return true
    }

    /// Rimuove l'event tap. Si può chiamare più volte.
    func stop() {
        guard let tap else { return }
        CGEvent.tapEnable(tap: tap, enable: false)
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        CFMachPortInvalidate(tap)
        self.tap = nil
        runLoopSource = nil
        resetGesture()
        logger.log("LISTENER_STOP")
    }

    fileprivate func handle(_ event: TapEvent) {
        switch event {
        case .mouseDown(let location):
            resetGesture()
            mouseDownLocation = location
            mouseDownChangeCount = NSPasteboard(name: .drag).changeCount
            mouseDownFrontmostApp = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
            mouseDownWindowOwner = bundleIdentifierOfWindowOwner(at: location)

        case .mouseDragged(let location):
            detectDragStart(at: location)

        case .mouseUp:
            if isDraggingFiles {
                logger.log(
                    "DRAG_END frecciaGiu=\(downArrowPressed ? "sì" : "no")",
                    describe(draggedFilePaths())
                )
            }
            resetGesture()

        case .downArrow(let isRepeat):
            guard isDraggingFiles, !isRepeat else { return }
            downArrowPressed = true
            logger.log("KEY_DOWN_ARROW")

        case .tapDisabled(let byTimeout):
            logger.log("LISTENER_DISABLED motivo=\(byTimeout ? "timeout" : "input utente")")
            if let tap {
                CGEvent.tapEnable(tap: tap, enable: true)
                logger.log("LISTENER_REENABLED")
            }
        }
    }

    /// Un trascinamento di file è iniziato quando, dopo la pressione del mouse, il pasteboard di
    /// trascinamento cambia e contiene file. Una selezione a rettangolo non lo cambia.
    private func detectDragStart(at location: CGPoint) {
        guard !gestureResolved, let origin = mouseDownLocation else { return }
        guard hypot(location.x - origin.x, location.y - origin.y) >= Self.dragThreshold else { return }
        guard NSPasteboard(name: .drag).changeCount != mouseDownChangeCount else { return }

        gestureResolved = true
        let paths = draggedFilePaths()
        guard !paths.isEmpty else { return }

        // La finestra sotto il puntatore vince; l'app in primo piano è il ripiego se non se ne trova una.
        let source = mouseDownWindowOwner ?? mouseDownFrontmostApp
        guard source == Self.finderBundleIdentifier else {
            logger.log("DRAG_IGNORED sorgente=\(source ?? "sconosciuta")")
            return
        }

        isDraggingFiles = true
        logger.log("DRAG_START sorgente=\(source ?? "") file=\(paths.count)", describe(paths))
    }

    private func draggedFilePaths() -> [String] {
        let urls = NSPasteboard(name: .drag).readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL] ?? []
        return urls.map(\.path)
    }

    private func describe(_ paths: [String]) -> [String] {
        paths.isEmpty ? ["(percorsi non disponibili)"] : paths
    }

    /// Livello delle finestre normali delle app. Il proprietario va cercato a questo livello o sotto
    /// (Scrivania): sopra ci sono finestre di sistema trasparenti, come quella del Dock, che coprono lo schermo.
    private static let normalWindowLevel = Int(CGWindowLevelForKey(.normalWindow))

    /// App proprietaria della finestra visibile più in alto nel punto dato, tra le finestre normali e la Scrivania.
    /// Serve perché il Finder permette di trascinare da una sua finestra in secondo piano senza
    /// diventare l'app attiva.
    private func bundleIdentifierOfWindowOwner(at point: CGPoint) -> String? {
        guard let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }
        for window in windows {
            guard
                let layer = window[kCGWindowLayer as String] as? Int, layer <= Self.normalWindowLevel,
                let alpha = window[kCGWindowAlpha as String] as? Double, alpha > 0,
                let boundsDictionary = window[kCGWindowBounds as String] as? NSDictionary,
                let bounds = CGRect(dictionaryRepresentation: boundsDictionary),
                bounds.contains(point),
                let pid = window[kCGWindowOwnerPID as String] as? Int
            else { continue }
            return NSRunningApplication(processIdentifier: pid_t(pid))?.bundleIdentifier
        }
        return nil
    }

    private func resetGesture() {
        mouseDownLocation = nil
        mouseDownChangeCount = 0
        mouseDownFrontmostApp = nil
        mouseDownWindowOwner = nil
        gestureResolved = false
        isDraggingFiles = false
        downArrowPressed = false
    }
}
