// SPDX-License-Identifier: GPL-2.0-only
// Command-driven debug shell. Shares the production rotation code via ROTATION_DEBUG.
import AppKit
import CoreGraphics
import IOKit
import Darwin

let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
    .appendingPathComponent("RotationDebug", isDirectory: true)
let requests = support.appendingPathComponent("requests", isDirectory: true)
let replies = support.appendingPathComponent("replies", isDirectory: true)

func validCommand(_ text: String) -> Bool {
    return ["status","modes","native","hidpi","hidpi save","repair on","repair off","quit","rotate 0","rotate 90","rotate 180","rotate 270"].contains(text)
}
func commandClient(_ text: String) -> Never {
    guard validCommand(text) else { fputs("Invalid debug command\n",stderr); exit(2) }
    guard let data = try? Data(contentsOf:support.appendingPathComponent("server.json")),
          let server = (try? JSONSerialization.jsonObject(with:data)) as? [String:Any],
          let pid = server["pid"] as? Int32, kill(pid,0) == 0 else {
        fputs("RotationDebug is not running. Open the installed debug app first.\n",stderr); exit(2)
    }
    let id = UUID().uuidString
    let request = requests.appendingPathComponent(id+".json")
    let reply = replies.appendingPathComponent(id+".json")
    do {
        let payload = try JSONSerialization.data(withJSONObject:["id":id,"command":text,"session":server["session"] ?? ""])
        try payload.write(to:request,options:.atomic)
    } catch { fputs("Cannot send command: \(error)\n",stderr); exit(2) }
    let deadline = Date().addingTimeInterval(45)
    while Date() < deadline {
        if let data = try? Data(contentsOf:reply),
           let response = (try? JSONSerialization.jsonObject(with:data)) as? [String:Any] {
            print(String(data:data,encoding:.utf8) ?? "Invalid reply")
            try? FileManager.default.removeItem(at:reply)
            exit(response["ok"] as? Bool == true ? 0 : 3)
        }
        usleep(50_000)
    }
    try? FileManager.default.removeItem(at:request)
    fputs("Command timed out; inspect debug logs before retrying.\n",stderr); exit(3)
}

final class Telemetry {
    private let queue = DispatchQueue(label:"org.yjmd2222.RotationDebug.telemetry")
    private var timer: DispatchSourceTimer?
    private let logURL: URL
    private let formatter = ISO8601DateFormatter()
    private var sequence = 0
    init() {
        let folder = FileManager.default.urls(for:.libraryDirectory,in:.userDomainMask).first!
            .appendingPathComponent("Logs/RotationDebug",isDirectory:true)
        try? FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        logURL = folder.appendingPathComponent("timeline.jsonl")
        formatter.formatOptions = [.withInternetDateTime,.withFractionalSeconds]
    }
    func start() {
        queue.async {
            let timer = DispatchSource.makeTimerSource(queue:self.queue)
            timer.schedule(deadline:.now(),repeating:.milliseconds(200),leeway:.milliseconds(10))
            timer.setEventHandler { [weak self] in self?.write(["event":"sample","displays":Self.displays(),"framebuffer":Self.framebuffer()]) }
            self.timer = timer; timer.resume()
            self.write(["event":"debug_started","pid":ProcessInfo.processInfo.processIdentifier,"automatic_orientation":false])
        }
    }
    func event(_ fields:[String:Any]) { queue.async { self.write(fields) } }
    func modes() {
        queue.async {
            var result = [[String:Any]]()
            for display in Self.displays() {
                guard let id = display["id"] as? UInt32 else { continue }
                let options = [kCGDisplayShowDuplicateLowResolutionModes:kCFBooleanTrue] as CFDictionary
                let modes = CGDisplayCopyAllDisplayModes(id,options) as? [CGDisplayMode] ?? []
                result.append(["id":id,"modes":modes.map { ["width":$0.width,"height":$0.height,"pixelWidth":$0.pixelWidth,"pixelHeight":$0.pixelHeight,"hz":$0.refreshRate,"ioFlags":$0.ioFlags,"modeID":$0.ioDisplayModeID] }])
            }
            self.write(["event":"mode_inventory","displays":result])
        }
    }
    static func displays() -> [[String:Any]] {
        var ids = [CGDirectDisplayID](repeating:0,count:32); var count:UInt32 = 0
        guard CGGetOnlineDisplayList(32,&ids,&count) == .success else { return [] }
        return ids.prefix(Int(count)).map { id in
            var result:[String:Any] = ["id":id,"builtin":CGDisplayIsBuiltin(id) != 0,"angle":CGDisplayRotation(id),"mirror":CGDisplayMirrorsDisplay(id),"inMirrorSet":CGDisplayIsInMirrorSet(id) != 0]
            if let mode = CGDisplayCopyDisplayMode(id) {
                result.merge(["width":mode.width,"height":mode.height,"pixelWidth":mode.pixelWidth,"pixelHeight":mode.pixelHeight,"hz":mode.refreshRate,"ioFlags":mode.ioFlags,"modeID":mode.ioDisplayModeID]) { _,new in new }
            }
            return result
        }
    }
    static func framebuffer() -> [String:Any] {
        var iterator:io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault,IOServiceMatching("AppleIntelFramebuffer"),&iterator) == KERN_SUCCESS else { return [:] }
        defer { IOObjectRelease(iterator) }
        while case let fb = IOIteratorNext(iterator), fb != 0 {
            defer { IOObjectRelease(fb) }
            func property(_ key:String) -> Any? { IORegistryEntryCreateCFProperty(fb,key as CFString,kCFAllocatorDefault,0)?.takeRetainedValue() }
            if property("FBReannounce-Probe") as? String != "attach" { continue }
            var result = [String:Any]()
            for key in ["IOFBTransform","IOFBCurrentPixelClock","IOFBCurrentPixelCount","FBReannounce-Status","FBReannounce-ReannouncePolicy"] {
                if let value = property(key) { result[key] = value }
            }
            return result
        }
        return [:]
    }
    private func write(_ fields:[String:Any]) {
        sequence += 1
        var record = fields
        record["seq"] = sequence; record["time"] = formatter.string(from:Date()); record["uptime"] = ProcessInfo.processInfo.systemUptime
        guard var bytes = try? JSONSerialization.data(withJSONObject:record,options:[.sortedKeys]) else { return }
        bytes.append(10)
        if let size = (try? FileManager.default.attributesOfItem(atPath:logURL.path))?[.size] as? NSNumber, size.intValue > 20_000_000 {
            let previous = logURL.deletingLastPathComponent().appendingPathComponent("timeline.previous.jsonl")
            try? FileManager.default.removeItem(at:previous); try? FileManager.default.moveItem(at:logURL,to:previous)
        }
        if !FileManager.default.fileExists(atPath:logURL.path) { FileManager.default.createFile(atPath:logURL.path,contents:nil) }
        if let file = FileHandle(forWritingAtPath:logURL.path) { file.seekToEndOfFile(); file.write(bytes); file.closeFile() }
    }
}

final class DebugDelegate: NSObject, NSApplicationDelegate {
    private var item:NSStatusItem?
    private var controller:RotationController?
    private var telemetry = Telemetry()
    private var poller:Timer?
    private var busy = false
    private var lockFD:Int32 = -1
    private let session = UUID().uuidString
    func applicationDidFinishLaunching(_ notification:Notification) {
        NSApp.setActivationPolicy(.accessory)
        do {
            for folder in [support,requests,replies] { try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700]) }
            // Share the production instance lock: the two controllers cannot run together.
            let production = support.deletingLastPathComponent().appendingPathComponent("ISHRotation",isDirectory:true)
            try FileManager.default.createDirectory(at:production,withIntermediateDirectories:true)
            lockFD = open(production.appendingPathComponent("instance.lock").path,O_CREAT|O_RDWR,S_IRUSR|S_IWUSR)
            guard lockFD >= 0, flock(lockFD,LOCK_EX|LOCK_NB) == 0 else { fputs("Another rotation app is running\n",stderr); exit(2) }
            let info = try JSONSerialization.data(withJSONObject:["pid":ProcessInfo.processInfo.processIdentifier,"session":session])
            try info.write(to:support.appendingPathComponent("server.json"),options:.atomic)
        } catch { fputs("Debug server setup failed: \(error)\n",stderr); exit(2) }
        controller = RotationController(menu:nil,defaults:.standard,monitoringOnly:true)
        telemetry.start()
        let menu = NSMenu(title:"RotationDebug")
        let status = NSMenuItem(title:"Command-driven debug · sensor rotation off",action:nil,keyEquivalent:"")
        menu.addItem(status)
        menu.addItem(.separator())
        let quit = NSMenuItem(title:"Quit RotationDebug",action:#selector(quitApp),keyEquivalent:"q"); quit.target = self; menu.addItem(quit)
        item = NSStatusBar.system.statusItem(withLength:NSStatusItem.squareLength)
        item?.button?.image = NSImage(systemSymbolName:"wrench.and.screwdriver",accessibilityDescription:"RotationDebug debug")
        item?.menu = menu
        poller = Timer.scheduledTimer(withTimeInterval:0.1,repeats:true) { [weak self] _ in self?.pollCommands() }
    }
    private func pollCommands() {
        guard !busy, let files = try? FileManager.default.contentsOfDirectory(at:requests,includingPropertiesForKeys:nil) else { return }
        guard let path = files.filter({$0.pathExtension == "json"}).sorted(by:{$0.lastPathComponent < $1.lastPathComponent}).first,
              let bytes = try? Data(contentsOf:path),let json = (try? JSONSerialization.jsonObject(with:bytes)) as? [String:Any],
              let id = json["id"] as? String, UUID(uuidString:id) != nil, let command = json["command"] as? String,validCommand(command) else { return }
        guard json["session"] as? String == session else {try? FileManager.default.removeItem(at:path);return}
        busy = true; try? FileManager.default.removeItem(at:path)
        telemetry.event(["event":"command_begin","id":id,"command":command])
        if command == "quit" { reply(id,command,"quitting"); DispatchQueue.main.asyncAfter(deadline:.now()+0.2) {NSApp.terminate(nil)}; return }
        if command == "modes" {telemetry.modes(); reply(id,command,"mode inventory recorded"); return}
        controller?.debugCommand(command) { [weak self] result in DispatchQueue.main.async {self?.reply(id,command,result)} }
    }
    private func reply(_ id:String,_ command:String,_ result:String) {
        let ok = !result.hasPrefix("error") && !result.hasPrefix("blocked") && result != "unknown command"
        let response:[String:Any] = ["id":id,"command":command,"ok":ok,"result":result,"displays":Telemetry.displays(),"framebuffer":Telemetry.framebuffer()]
        telemetry.event(["event":"command_end","id":id,"command":command,"result":result])
        if let bytes = try? JSONSerialization.data(withJSONObject:response,options:[.sortedKeys]) {try? bytes.write(to:replies.appendingPathComponent(id+".json"),options:.atomic)}
        busy = false
    }
    @objc private func quitApp() {NSApp.terminate(nil)}
    func applicationWillTerminate(_ notification:Notification) {
        poller?.invalidate();controller?.stop();try? FileManager.default.removeItem(at:support.appendingPathComponent("server.json"))
        if lockFD >= 0 {close(lockFD)}
    }
}
if CommandLine.arguments.count == 3,CommandLine.arguments[1] == "--command" {commandClient(CommandLine.arguments[2])}
let delegate = DebugDelegate()
let app = NSApplication.shared
app.delegate = delegate
app.run()
