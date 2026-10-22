// Speakeasy: stops macOS Dictation when you press Return, then lets the Return through.
//
// Dictation state comes from DictationIM's log lines, read via `log stream`:
//   "Keyboard Dictation: Update Dictation State: N"  1 = listening, 2 = stopping, 0 = stopped
//   "+[AFAggregator logDictation<Outcome>]"          session finished (Succeeded, Cancelled, ...)
// When Return is pressed while listening, we swallow it and press the focused app's
// Edit > Stop Dictation menu item (AXIdentifier "stopDictation:"). That takes the same path
// as the mic key and finishes transcribing pending audio. Escape is only a fallback for apps
// without that item, because Escape cancels and drops audio still being processed. Once the
// session reports its outcome we replay the Return. A Return that lands during state 2
// makes Dictation resume listening, so we must wait for the full stop.

import AppKit
import ApplicationServices
import ServiceManagement

let kReturn: CGKeyCode = 36
let kKeypadEnter: CGKeyCode = 76
let kEscape: CGKeyCode = 53
// Tags our own synthetic events so the tap lets them pass.
let syntheticMarker: Int64 = 0x5350_4B45 // "SPKE"
let stopTimeout: TimeInterval = 3.0
let stopDictationIdentifier = "stopDictation:"
let enabledKey = "enabled"

// MARK: - Dictation state from the system log

final class DictationMonitor {
    private(set) var isListening = false
    // Bumped each time a session reports its outcome.
    private(set) var finishedSessions = 0
    var onChange: ((Bool) -> Void)?
    private var process: Process?

    private static let predicate =
        #"process == "DictationIM" AND (eventMessage CONTAINS "Update Dictation State" OR eventMessage CONTAINS "AFAggregator logDictation")"#

    func start() {
        seedFromRecentLog()
        launchStream()
    }

    // If we launch mid-session, pick up the last known state.
    private func seedFromRecentLog() {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/log")
        p.arguments = ["show", "--last", "2m", "--style", "compact", "--predicate", Self.predicate]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        let lines = String(decoding: data, as: UTF8.self).split(separator: "\n")
        if let state = lines.compactMap({ Self.parseState(String($0)) }).last {
            isListening = (state != 0)
        }
    }

    private func launchStream() {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/log")
        p.arguments = ["stream", "--style", "compact", "--predicate", Self.predicate]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice

        var buffer = ""
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let chunk = String(decoding: handle.availableData, as: UTF8.self)
            buffer += chunk
            while let nl = buffer.firstIndex(of: "\n") {
                let line = String(buffer[..<nl])
                buffer.removeSubrange(...nl)
                if let state = Self.parseState(line) {
                    DispatchQueue.main.async { self?.update(state != 0) }
                } else if Self.isSessionFinished(line) {
                    DispatchQueue.main.async { self?.finishedSessions += 1 }
                }
            }
        }
        p.terminationHandler = { [weak self] _ in
            pipe.fileHandleForReading.readabilityHandler = nil
            // Restart if the stream dies; assume not listening meanwhile.
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                self?.update(false)
                self?.launchStream()
            }
        }
        do {
            try p.run()
            process = p
        } catch {
            NSLog("Speakeasy: could not start log stream: \(error)")
        }
    }

    private func update(_ listening: Bool) {
        guard listening != isListening else { return }
        isListening = listening
        onChange?(listening)
    }

    static func parseState(_ line: String) -> Int? {
        guard let r = line.range(of: "Update Dictation State: ") else { return nil }
        return Int(line[r.upperBound...].prefix { $0.isNumber })
    }

    static func isSessionFinished(_ line: String) -> Bool {
        line.contains("AFAggregator logDictation") && !line.contains("logDictationStarted")
    }

    func stop() {
        process?.terminationHandler = nil
        process?.terminate()
    }
}

// MARK: - Return interception

final class ReturnInterceptor {
    let monitor: DictationMonitor
    var enabled = true
    private var tap: CFMachPort?
    private var pending = false          // a Return is being held while Dictation stops
    private var swallowKeyUp: Set<CGKeyCode> = []

    init(monitor: DictationMonitor) { self.monitor = monitor }

    var isInstalled: Bool { tap != nil }

    func install() -> Bool {
        guard tap == nil else { return true }
        let mask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap,
                                          place: .headInsertEventTap,
                                          options: .defaultTap,
                                          eventsOfInterest: CGEventMask(mask),
                                          callback: { _, type, event, refcon in
                                              let me = Unmanaged<ReturnInterceptor>.fromOpaque(refcon!).takeUnretainedValue()
                                              return me.handle(type: type, event: event)
                                          },
                                          userInfo: refcon) else { return false }
        self.tap = tap
        let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        if event.getIntegerValueField(.eventSourceUserData) == syntheticMarker {
            return Unmanaged.passUnretained(event)
        }
        let key = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
        guard key == kReturn || key == kKeypadEnter else { return Unmanaged.passUnretained(event) }

        if type == .keyUp {
            if swallowKeyUp.remove(key) != nil { return nil }
            return Unmanaged.passUnretained(event)
        }

        // keyDown
        if pending { return nil } // drop autorepeat while we're stopping Dictation
        guard enabled, monitor.isListening else { return Unmanaged.passUnretained(event) }

        pending = true
        swallowKeyUp.insert(key)
        let flags = event.flags
        DispatchQueue.main.async { self.stopDictationThenReturn(key: key, flags: flags) }
        return nil
    }

    private func stopDictationThenReturn(key: CGKeyCode, flags: CGEventFlags) {
        let sessionsBefore = monitor.finishedSessions
        let usedMenu = pressStopDictationMenuItem()
        if !usedMenu { postKey(kEscape, flags: []) }
        NSLog("Speakeasy: Return while dictating; stopped via %@", usedMenu ? "menu" : "Escape")
        let deadline = Date().addingTimeInterval(stopTimeout)
        func waitThenReturn() {
            // Escape discards pending audio, so state 0 is enough there; the menu path
            // keeps transcribing after state 0 until the session reports its outcome.
            let done = usedMenu ? monitor.finishedSessions > sessionsBefore : !monitor.isListening
            if !done && Date() < deadline {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.01, execute: waitThenReturn)
                return
            }
            NSLog("Speakeasy: replaying Return (%@)", done ? "session finished" : "timed out")
            postKey(key, flags: flags)
            pending = false
        }
        waitThenReturn()
    }

    // Presses Edit > Stop Dictation in the frontmost app. Returns false if it has none.
    private func pressStopDictationMenuItem() -> Bool {
        guard let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier else { return false }
        let app = AXUIElementCreateApplication(pid)
        guard let bar: AXUIElement = axAttribute(app, kAXMenuBarAttribute) else { return false }
        for top in axChildren(bar) {
            for menu in axChildren(top) {
                for item in axChildren(menu) where axAttribute(item, "AXIdentifier") as String? == stopDictationIdentifier {
                    return AXUIElementPerformAction(item, kAXPressAction as CFString) == .success
                }
            }
        }
        return false
    }

    private func axAttribute<T>(_ element: AXUIElement, _ name: String) -> T? {
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value as? T
    }

    private func axChildren(_ element: AXUIElement) -> [AXUIElement] {
        axAttribute(element, kAXChildrenAttribute) ?? []
    }

    private func postKey(_ key: CGKeyCode, flags: CGEventFlags) {
        let src = CGEventSource(stateID: .hidSystemState)
        for down in [true, false] {
            guard let e = CGEvent(keyboardEventSource: src, virtualKey: key, keyDown: down) else { continue }
            e.flags = flags
            e.setIntegerValueField(.eventSourceUserData, value: syntheticMarker)
            e.post(tap: .cgSessionEventTap)
        }
    }
}

// MARK: - Menu bar app

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let monitor = DictationMonitor()
    lazy var interceptor = ReturnInterceptor(monitor: monitor)
    var statusItem: NSStatusItem!
    var permissionTimer: Timer?

    func applicationDidFinishLaunching(_ note: Notification) {
        UserDefaults.standard.register(defaults: [enabledKey: true])
        interceptor.enabled = UserDefaults.standard.bool(forKey: enabledKey)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        monitor.onChange = { [weak self] _ in self?.updateIcon() }
        monitor.start()

        registerLoginItemOnFirstLaunch()
        ensureAccessibility(prompt: true)
        updateIcon()
    }

    // MARK: Accessibility

    private func ensureAccessibility(prompt: Bool) {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt] as CFDictionary
        if AXIsProcessTrustedWithOptions(opts), interceptor.install() {
            permissionTimer?.invalidate()
            permissionTimer = nil
            updateIcon()
            return
        }
        // Poll until the user grants access in System Settings.
        if permissionTimer == nil {
            permissionTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
                self?.ensureAccessibility(prompt: false)
            }
        }
        updateIcon()
    }

    // MARK: Login item

    private func registerLoginItemOnFirstLaunch() {
        let key = "didRegisterLoginItem"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        do {
            try SMAppService.mainApp.register()
            UserDefaults.standard.set(true, forKey: key)
        } catch {
            NSLog("Speakeasy: login item registration failed: \(error)")
        }
    }

    // MARK: Icon and menu

    private func updateIcon() {
        let symbol: String
        if !interceptor.isInstalled {
            symbol = "exclamationmark.triangle"
        } else if !interceptor.enabled {
            symbol = "return"
        } else {
            symbol = monitor.isListening ? "mic.fill" : "return"
        }
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Speakeasy")
        image?.isTemplate = true
        statusItem.button?.image = image
        statusItem.button?.appearsDisabled = interceptor.isInstalled && !interceptor.enabled
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let status: String
        if !interceptor.isInstalled {
            status = "Needs Accessibility permission"
        } else if !interceptor.enabled {
            status = "Off"
        } else {
            status = monitor.isListening ? "Dictation is on: Return will stop it" : "Waiting for Dictation"
        }
        let header = NSMenuItem(title: status, action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())

        if !interceptor.isInstalled {
            menu.addItem(item("Open Accessibility Settings…", #selector(openAccessibility)))
        }

        let toggle = item("Stop Dictation on Return", #selector(toggleEnabled))
        toggle.state = interceptor.enabled ? .on : .off
        menu.addItem(toggle)

        let login = item("Open at Login", #selector(toggleLogin))
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)

        menu.addItem(.separator())
        menu.addItem(item("Quit Speakeasy", #selector(quit), key: "q"))
    }

    private func item(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let i = NSMenuItem(title: title, action: action, keyEquivalent: key)
        i.target = self
        return i
    }

    @objc private func toggleEnabled() {
        interceptor.enabled.toggle()
        UserDefaults.standard.set(interceptor.enabled, forKey: enabledKey)
        updateIcon()
    }

    @objc private func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            NSLog("Speakeasy: login item toggle failed: \(error)")
        }
    }

    @objc private func openAccessibility() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    @objc private func quit() {
        monitor.stop()
        NSApp.terminate(nil)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
