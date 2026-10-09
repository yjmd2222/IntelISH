// SPDX-License-Identifier: GPL-2.0-only
// Copyright 2026 yjmd2222. Rotation engine extracted from the HP YogaSMC fork.
import AppKit
import ServiceManagement
import Darwin

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var item: NSStatusItem?
    private var controller: RotationController?
    private var instanceFD: Int32 = -1
    private var loginItem: NSMenuItem?
    private let diagnostics = CommandLine.arguments.contains("--diagnose")

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        if !diagnostics && !acquireInstance() { NSApp.terminate(nil); return }
        let menu = NSMenu(title: "ISHRotation")
        controller = RotationController(menu: diagnostics ? nil : menu, defaults: .standard, monitoringOnly: diagnostics)
        if diagnostics {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                print("Monitoring-only diagnostics: ~/Library/Logs/ISHRotation/rotation.log")
                NSApp.terminate(nil)
            }
            return
        }
        menu.addItem(.separator())
        loginItem = NSMenuItem(title: "Start at Login", action: #selector(toggleLogin), keyEquivalent: "")
        loginItem?.target = self; menu.addItem(loginItem!)
        let logs = NSMenuItem(title: "Open Logs", action: #selector(openLogs), keyEquivalent: "")
        logs.target = self; menu.addItem(logs)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit ISHRotation", action: #selector(quitApp), keyEquivalent: "q")
        quit.target = self; menu.addItem(quit)
        menu.delegate = self
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item?.button?.image = NSImage(systemSymbolName: "rotate.right", accessibilityDescription: "ISHRotation")
        item?.button?.toolTip = "IntelISH Display Rotation"
        item?.menu = menu
        refreshLogin()
        loginLog("Started; main-app login status=\(SMAppService.mainApp.status.rawValue)")
    }

    private func acquireInstance() -> Bool {
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("ISHRotation", isDirectory: true)
        do { try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true) }
        catch { loginLog("Cannot create instance directory: \(error)"); return false }
        instanceFD = open(folder.appendingPathComponent("instance.lock").path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard instanceFD >= 0, flock(instanceFD, LOCK_EX | LOCK_NB) == 0 else {
            loginLog("Another ISHRotation instance is running, or instance lock failed")
            if instanceFD >= 0 { close(instanceFD); instanceFD = -1 }
            return false
        }
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        controller?.stop()
        if instanceFD >= 0 { close(instanceFD); instanceFD = -1 }
    }
    func menuWillOpen(_ menu: NSMenu) { refreshLogin() }
    private func refreshLogin() {
        let status = SMAppService.mainApp.status
        loginItem?.state = status == .enabled || status == .requiresApproval ? .on : .off
        loginItem?.title = status == .requiresApproval ? "Start at Login (Allow in Settings)" : "Start at Login"
    }
    @objc private func toggleLogin() {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled || service.status == .requiresApproval { try service.unregister() }
            else { try service.register() }
            refreshLogin()
            loginLog("Login toggle status=\(service.status.rawValue)")
            if service.status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
        } catch {
            loginLog("Login registration failed: \(error)")
            let alert = NSAlert(); alert.messageText = "Could not change login startup"
            alert.informativeText = error.localizedDescription; alert.runModal()
        }
    }
    @objc private func openLogs() {
        NSWorkspace.shared.open(FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Logs/ISHRotation", isDirectory: true))
    }
    @objc private func quitApp() { NSApp.terminate(nil) }
    private func loginLog(_ text: String) {
        let directory = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Logs/ISHRotation", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("login.log")
        if let size = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? NSNumber,
           size.intValue > 262144 { try? FileManager.default.removeItem(at: url) }
        if !FileManager.default.fileExists(atPath: url.path) { FileManager.default.createFile(atPath: url.path, contents: nil) }
        if let bytes = "\(Date()) \(text)\n".data(using: .utf8), let file = FileHandle(forWritingAtPath: url.path) {
            file.seekToEndOfFile(); file.write(bytes); file.closeFile()
        }
    }
}
let delegate = AppDelegate()
let app = NSApplication.shared
app.delegate = delegate
app.run()
