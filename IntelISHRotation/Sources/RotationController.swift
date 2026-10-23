// SPDX-License-Identifier: GPL-2.0-only
// IntelISH is an independent companion kext; no YogaSMC user-client coupling.
import AppKit
import CoreGraphics
import IOKit
import Darwin

final class RotationController: NSObject {
    private let queue = DispatchQueue(label: "org.yjmd2222.ISHRotation.rotation")
    private let defaults: UserDefaults
    private var timer: DispatchSourceTimer?
    private var policy = RotationPolicy()
    private var enabled: Bool
    private var locked: Bool
    private var sleeping = false
    private var lastTimestamp: UInt64 = 0
    private var lastAttempt: TimeInterval = -10
    private var status = "Starting"
    private var observedAngle: Int32?
    private var observedTopology = ""
    private var observedMode = ""
    private var modeStableSince: TimeInterval = 0
    private var scalingWindowUntil: TimeInterval = 0
    private var lastScalingAttempt: TimeInterval = -10
    private var scalingAttempts = 0
    private var preferredLongEdge = 0
    private var preferredShortEdge = 0
    private var framework: UnsafeMutableRawPointer?
    private var displayClass: AnyClass?
    private var autoItem: NSMenuItem?
    private var lockItem: NSMenuItem?
    private var statusItem: NSMenuItem?
    private let logURL: URL?
#if ROTATION_DEBUG
    private var debugRepair = false
#endif

    init(menu: NSMenu?, defaults: UserDefaults, monitoringOnly: Bool = false) {
        self.defaults = defaults
        enabled = !monitoringOnly && defaults.bool(forKey: "AutoRotate")
        locked = defaults.bool(forKey: "RotationLocked")
        preferredLongEdge = defaults.integer(forKey: "HiDPILongEdge")
        preferredShortEdge = defaults.integer(forKey: "HiDPIShortEdge")
#if ROTATION_DEBUG
        let logDirectory = "Logs/RotationDebug"
#else
        let logDirectory = "Logs/IntelISHRotation"
#endif
        let directory = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first?
            .appendingPathComponent(logDirectory, isDirectory: true)
        if let directory = directory {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: nil)
        }
        logURL = directory?.appendingPathComponent("rotation.log")
        super.init()
        if let menu = menu {
            let submenu = menu
            autoItem = NSMenuItem(title: "Auto-Rotate", action: #selector(toggleAuto), keyEquivalent: "")
            autoItem?.target = self; submenu.addItem(autoItem!)
            lockItem = NSMenuItem(title: "Rotation Lock", action: #selector(toggleLock), keyEquivalent: "")
            lockItem?.target = self; submenu.addItem(lockItem!)
            submenu.addItem(NSMenuItem.separator())
            statusItem = NSMenuItem(title: "Checking motion sensor…", action: nil, keyEquivalent: "")
            submenu.addItem(statusItem!)
        }
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(willSleep), name: NSWorkspace.willSleepNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(didWake), name: NSWorkspace.didWakeNotification, object: nil)
        queue.async { [weak self] in self?.start() }
    }

    func stop() {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        queue.async { [weak self] in self?.timer?.cancel(); self?.timer = nil }
    }

    @objc private func toggleAuto() {
        queue.async {
            self.enabled.toggle(); self.defaults.set(self.enabled, forKey: "AutoRotate")
            self.policy.reset(); self.lastTimestamp = 0
            self.log("Auto-Rotate=\(self.enabled)"); self.poll()
        }
    }
    @objc private func toggleLock() {
        queue.async {
            self.locked.toggle(); self.defaults.set(self.locked, forKey: "RotationLocked")
            self.policy.reset(); self.lastTimestamp = 0
            self.log("Rotation Lock=\(self.locked)"); self.poll()
        }
    }
    @objc private func willSleep() { queue.async { self.sleeping = true; self.policy.reset() } }
    @objc private func didWake() {
        queue.async { self.sleeping = false; self.lastTimestamp = 0; self.lastAttempt = ProcessInfo.processInfo.systemUptime; self.policy.reset() }
    }
    private func start() {
        // Only the tested Ventura route. Do not invoke an unsupported private API.
        if ProcessInfo.processInfo.operatingSystemVersion.majorVersion == 13 {
            framework = dlopen("/System/Library/PrivateFrameworks/MonitorPanel.framework/MonitorPanel", RTLD_NOW)
            if framework != nil { displayClass = NSClassFromString("MPDisplay") }
        }
        log("Started; auto=\(enabled) lock=\(locked)")
        logTopology("Startup")
        let source = DispatchSource.makeTimerSource(queue: queue)
        source.schedule(deadline: .now(), repeating: .milliseconds(200), leeway: .milliseconds(30))
        source.setEventHandler { [weak self] in self?.poll() }
        timer = source; source.resume()
    }
    private func property(_ service: io_service_t, _ key: String) -> Any? {
        return IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
    }
    private func internalDisplay() -> CGDirectDisplayID? {
        var ids = [CGDirectDisplayID](repeating: 0, count: 16); var count: UInt32 = 0
        guard CGGetOnlineDisplayList(16, &ids, &count) == .success else { return nil }
        return ids.prefix(Int(count)).first { CGDisplayIsBuiltin($0) != 0 }
    }
    private func reannounceReady(requireGuard: Bool = false) -> Bool {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("AppleIntelFramebuffer"), &iterator) == KERN_SUCCESS else { return false }
        defer { IOObjectRelease(iterator) }
        while case let fb = IOIteratorNext(iterator), fb != 0 {
            let ready = property(fb, "FBReannounce-Resolve") as? String == "connection-change symbol resolved"
                && property(fb, "FBReannounce-Probe") as? String == "attach"
                && (!requireGuard || property(fb, "FBReannounce-WindowServerGuard") as? String == "registered")
            IOObjectRelease(fb)
            if ready { return true }
        }
        return false
    }
    private func publish(_ text: String, ready: Bool) {
        if status != text { status = text; log(text) }
        let on = enabled, lock = locked
        DispatchQueue.main.async { [weak self] in
            self?.autoItem?.state = on ? .on : .off
            self?.autoItem?.isEnabled = ready || on
            self?.lockItem?.state = lock ? .on : .off
            self?.lockItem?.isEnabled = on
            self?.statusItem?.title = text
        }
    }
    // Migration guard only; the app has no YogaSMC driver dependency.
    private func legacyControllerActive() -> Bool {
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: "org.zhen.YogaSMCNC")
        guard running.contains(where: {
            guard let url = $0.bundleURL, let bundle = Bundle(url: url) else { return true }
            return bundle.object(forInfoDictionaryKey: "ISHRotationControllerEmbedded") as? Bool != false
        }), let legacy = UserDefaults(suiteName: "org.zhen.YogaSMC") else { return false }
        legacy.synchronize()
        return legacy.bool(forKey: "AutoRotate")
    }
    private func poll() {
        guard !sleeping else { return }
#if ROTATION_DEBUG
        debugPoll()
        return
#else
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IntelISH"))
        guard service != 0 else { policy.reset(); publish("Motion sensor unavailable", ready: false); return }
        defer { IOObjectRelease(service) }
        guard property(service, "AccelControlsVerified") as? Bool == true,
              let sample = property(service, "AccelSample") as? [String: Any],
              let timestamp = sample["TimestampNS"] as? NSNumber,
              let rawX = sample["RawX"] as? NSNumber, let rawY = sample["RawY"] as? NSNumber,
              let rawZ = sample["RawZ"] as? NSNumber,
              property(service, "AccelAxis-X") as? String == "bit=152 width=32 min=-2147483648 max=2147483647 unit=0x0 exponent=-6" else {
            policy.reset(); publish("Waiting for motion samples", ready: false); return
        }
        // Samples use mach uptime (pauses during sleep), not wall clock.
        var info = mach_timebase_info_data_t(); mach_timebase_info(&info)
        let nowNS = Double(mach_absolute_time()) * Double(info.numer) / Double(info.denom)
        let sampleNS = timestamp.uint64Value
        guard nowNS >= Double(sampleNS), nowNS - Double(sampleNS) < 2_000_000_000 else {
            policy.reset(); publish("Motion samples stale", ready: false); return
        }
        guard displayClass != nil else { policy.reset(); publish("Rotation unavailable on this macOS", ready: false); return }
        // Rotation previously crashed WindowServer without WSNullGuard.
        // Lilu plugin service is active but does not call registerService.
        let guardService = IORegistryEntryFromPath(kIOMainPortDefault, "IOService:/IOResources/WSNullGuard")
        let guarded = guardService != 0 && IOObjectConformsTo(guardService, "WSNullGuard") != 0
        if guardService != 0 { IOObjectRelease(guardService) }
        guard (guarded || reannounceReady(requireGuard: true)), reannounceReady() else { policy.reset(); publish("Rotation support unavailable", ready: false); return }
        guard let display = internalDisplay() else { policy.reset(); publish("Internal display unavailable", ready: false); return }
        let angle = Int32(CGDisplayRotation(display))
        let uptime = ProcessInfo.processInfo.systemUptime
        let topology = onlineDisplays()?.map { "\($0):\(CGDisplayMirrorsDisplay($0))" }.joined(separator: ",") ?? ""
        if topology != observedTopology || observedAngle != angle {
            observedTopology = topology
            scalingWindowUntil = uptime + 12
            scalingAttempts = 0
        }
        if observedAngle != angle { observedAngle = angle; log("Display angle=\(angle)"); logTopology("Orientation observed") }
        guard !legacyControllerActive() else {
            policy.reset(); publish("Turn off Auto-Rotate in YogaSMCNC", ready: false); return
        }
        if enabled { preserveHiDPI(display, angle: angle, now: uptime) }
        guard enabled, !locked else {
            policy.reset(); publish(locked && enabled ? "Locked at \(angle)°" : "Auto-Rotate off", ready: true); return
        }
        publish("Auto-Rotate on · \(angle)°", ready: true)
        guard sampleNS != lastTimestamp else { return }
        lastTimestamp = sampleNS
        let now = ProcessInfo.processInfo.systemUptime
        let x = Double(Int64(bitPattern: rawX.uint64Value)) / 1_000_000
        let y = Double(Int64(bitPattern: rawY.uint64Value)) / 1_000_000
        let z = Double(Int64(bitPattern: rawZ.uint64Value)) / 1_000_000
        guard let desired = policy.update(x: x, y: y, z: z, now: now),
              now - lastAttempt > 3 else { return }
        // Mirroring shares a landscape drawable area with the external display.
        // Leave the internal display's mirror set before requesting portrait,
        // even when it is already at that angle (e.g. mirroring was enabled later).
        if (desired == 90 || desired == 270), CGDisplayIsInMirrorSet(display) != 0 {
            lastAttempt = now; policy.reset()
            let transitionStart = ProcessInfo.processInfo.systemUptime
            log("Portrait angle=\(desired): extending and rotating without settle delay")
            guard extendInternalDisplay(display) else {
                publish("Unable to leave mirrored mode", ready: true); return
            }
            // These APIs cannot share a configuration transaction. Request
            // rotation immediately after extension completes, using the fresh ID.
            guard let currentDisplay = internalDisplay() else {
                log("Immediate rotation deferred: internal display temporarily unavailable")
                // Retry on the next fresh stable sample, without the old 3s pause.
                lastAttempt = now - 3
                return
            }
            let currentAngle = Int32(CGDisplayRotation(currentDisplay))
            if currentAngle != desired {
                log(String(format: "Immediate rotation angle=%d after extension %.3fs", desired,
                           ProcessInfo.processInfo.systemUptime - transitionStart))
                logTopology("Before immediate rotation")
                if !rotate(currentDisplay, to: desired) {
                    publish("Rotation request unavailable", ready: true)
                }
            } else {
                log("Already at \(desired)° after leaving mirror set")
            }
            log(String(format: "Extension/rotation requests finished in %.3fs",
                       ProcessInfo.processInfo.systemUptime - transitionStart))
            return
        }
        guard desired != angle else { return }
        lastAttempt = now; policy.reset()
        log("Request angle=\(desired) raw-g=(\(x),\(y),\(z))")
        logTopology("Before rotation")
        if !rotate(display, to: desired) { publish("Rotation request unavailable", ready: true) }
#endif
    }
#if ROTATION_DEBUG
    // This build never reads acceleration for policy or requests orientation by itself.
    private func debugPoll() {
        guard let id = internalDisplay() else { return }
        let angle = Int32(CGDisplayRotation(id))
        if observedAngle != angle {
            observedAngle = angle; scalingWindowUntil = ProcessInfo.processInfo.systemUptime + 12; scalingAttempts = 0
            logTopology("Debug orientation observed")
        }
        if debugRepair && !legacyControllerActive() {
            preserveHiDPI(id, angle: angle, now: ProcessInfo.processInfo.systemUptime)
        }
    }
    func debugCommand(_ command: String, completion: @escaping (String) -> Void) {
        queue.async {
            self.log("DEBUG command begin: \(command)")
            var result = "unknown command"
            let fields = command.split(separator: " ").map(String.init)
            if command == "status" { self.logTopology("Debug status"); result = "status recorded" }
            else if command == "repair on" || command == "repair off" {
                self.debugRepair = command == "repair on"
                self.scalingWindowUntil = ProcessInfo.processInfo.systemUptime + 12; self.scalingAttempts = 0
                result = "automatic HiDPI repair=\(self.debugRepair)"
            } else if self.legacyControllerActive() { result = "blocked: legacy YogaSMC rotation enabled" }
            else if !self.reannounceReady(requireGuard: true) { result = "blocked: display support unavailable" }
            else if let id = self.internalDisplay() {
                if fields.count == 2, fields[0] == "rotate", let angle = Int32(fields[1]), [0,90,180,270].contains(angle) {
                    self.logTopology("Before debug rotation")
                    if (angle == 90 || angle == 270) && CGDisplayIsInMirrorSet(id) != 0 && !self.extendInternalDisplay(id) {
                        result = "error: could not leave mirror set"
                    } else if let freshID = self.internalDisplay() {
                        self.scalingWindowUntil = ProcessInfo.processInfo.systemUptime + 12; self.scalingAttempts = 0
                        result = Int32(CGDisplayRotation(freshID)) == angle ? "already at \(angle)" : (self.rotate(freshID, to: angle) ? "rotation requested \(angle)" : "error: rotation request failed")
                        self.logTopology("After debug rotation call")
                    } else { result = "error: display unavailable after extending" }
                } else if command == "native" || command == "hidpi" || command == "hidpi save" {
                    result = self.debugSetMode(id, hiDPI: command != "native", permanent: command == "hidpi save")
                }
            } else { result = "error: internal display unavailable" }
            self.log("DEBUG command end: \(command): \(result)")
            completion(result)
        }
    }
    private func debugSetMode(_ id: CGDirectDisplayID, hiDPI: Bool, permanent: Bool) -> String {
        guard CGDisplayIsInMirrorSet(id) == 0, let current = CGDisplayCopyDisplayMode(id) else { return "error: requires unmirrored display" }
        let options = [kCGDisplayShowDuplicateLowResolutionModes:kCFBooleanTrue] as CFDictionary
        guard let modes = CGDisplayCopyAllDisplayModes(id, options) as? [CGDisplayMode] else { return "error: modes unavailable" }
        var target: CGDisplayMode?
        if hiDPI {
            let descriptions = modes.map { HiDPIModeDescription(width:$0.width, height:$0.height, pixelWidth:$0.pixelWidth, pixelHeight:$0.pixelHeight, refreshRate:$0.refreshRate) }
            let long = preferredLongEdge > 0 ? preferredLongEdge : max(current.pixelWidth,current.pixelHeight)/2
            let short = preferredShortEdge > 0 ? preferredShortEdge : min(current.pixelWidth,current.pixelHeight)/2
            let angle = Int32(CGDisplayRotation(id))
            if let index = HiDPIModePolicy.choose(descriptions,longEdge:long,shortEdge:short,portrait:angle == 90 || angle == 270,refreshRate:current.refreshRate) { target = modes[index] }
        } else {
            target = modes.filter { $0.width == current.pixelWidth && $0.height == current.pixelHeight && $0.width == $0.pixelWidth && $0.height == $0.pixelHeight }.min { abs($0.refreshRate-current.refreshRate) < abs($1.refreshRate-current.refreshRate) }
        }
        guard let mode = target else { return "error: matching mode absent" }
        if !permanent && current.width == mode.width && current.height == mode.height && current.pixelWidth == mode.pixelWidth && current.pixelHeight == mode.pixelHeight && abs(current.refreshRate-mode.refreshRate) < 0.1 {
            return "mode already selected logical=\(mode.width)x\(mode.height)"
        }
        let result = permanent ? saveDisplayMode(id, mode: mode) : CGDisplaySetDisplayMode(id,mode,nil)
        logTopology("After debug mode selection")
        return "\(result == .success ? "mode set" : "error: mode set") permanent=\(permanent) result=\(result.rawValue) logical=\(mode.width)x\(mode.height) backing=\(mode.pixelWidth)x\(mode.pixelHeight)"
    }
#endif
    private func preserveHiDPI(_ id: CGDirectDisplayID, angle: Int32, now: TimeInterval) {
        guard CGDisplayIsInMirrorSet(id) == 0, let current = CGDisplayCopyDisplayMode(id) else { return }
        let signature = "\(current.width)x\(current.height)/\(current.pixelWidth)x\(current.pixelHeight)"
        if signature != observedMode {
            observedMode = signature; modeStableSince = now
            logTopology("Scaling observed")
        }
        // Remember real HiDPI choices, normalized so they survive orientation.
        if current.pixelWidth >= current.width * 2 && current.pixelHeight >= current.height * 2 {
            let long = max(current.width, current.height), short = min(current.width, current.height)
            if long != preferredLongEdge || short != preferredShortEdge {
                preferredLongEdge = long; preferredShortEdge = short
                defaults.set(long, forKey: "HiDPILongEdge"); defaults.set(short, forKey: "HiDPIShortEdge")
                log("Remember HiDPI logical edges=\(long)x\(short)")
            }
            return
        }
        // Limit repair to startup/rotation/topology changes. A later deliberate
        // user selection of 1x is not continuously overridden.
        guard now < scalingWindowUntil, now - modeStableSince > 1,
              now - lastScalingAttempt > 3, scalingAttempts < 2, !reannouncePending() else { return }
        let long = preferredLongEdge > 0 ? preferredLongEdge : max(current.pixelWidth, current.pixelHeight) / 2
        let short = preferredShortEdge > 0 ? preferredShortEdge : min(current.pixelWidth, current.pixelHeight) / 2
        let options = [kCGDisplayShowDuplicateLowResolutionModes: kCFBooleanTrue] as CFDictionary
        guard let modes = CGDisplayCopyAllDisplayModes(id, options) as? [CGDisplayMode] else { return }
        let descriptions = modes.map { HiDPIModeDescription(width: $0.width, height: $0.height,
            pixelWidth: $0.pixelWidth, pixelHeight: $0.pixelHeight, refreshRate: $0.refreshRate) }
        guard let index = HiDPIModePolicy.choose(descriptions, longEdge: long, shortEdge: short,
            portrait: angle == 90 || angle == 270, refreshRate: current.refreshRate) else { return }
        lastScalingAttempt = now; scalingAttempts += 1
        let target = modes[index]
        log("Save HiDPI logical=\(target.width)x\(target.height) backing=\(target.pixelWidth)x\(target.pixelHeight) hz=\(target.refreshRate), attempt=\(scalingAttempts)")
        let result = saveDisplayMode(id, mode: target)
        log("Save HiDPI permanent result=\(result.rawValue)")
        logTopology("After HiDPI restore")
    }
    // Save the selected mode for this display/orientation/topology, rather than
    // leaving WindowServer's saved native portrait choice to win next rotation.
    private func saveDisplayMode(_ id: CGDirectDisplayID, mode: CGDisplayMode) -> CGError {
        var config: CGDisplayConfigRef?
        let begin = CGBeginDisplayConfiguration(&config)
        guard begin == .success, let transaction = config else { return begin == .success ? .failure : begin }
        let configure = CGConfigureDisplayWithDisplayMode(transaction, id, mode, nil)
        guard configure == .success else { CGCancelDisplayConfiguration(transaction); return configure }
        return CGCompleteDisplayConfiguration(transaction, .permanently)
    }
    private func reannouncePending() -> Bool {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("AppleIntelFramebuffer"), &iterator) == KERN_SUCCESS else { return true }
        defer { IOObjectRelease(iterator) }
        while case let fb = IOIteratorNext(iterator), fb != 0 {
            let attached = property(fb, "FBReannounce-Probe") as? String == "attach"
            let state = property(fb, "FBReannounce-Status") as? String
            IOObjectRelease(fb)
            if attached { return state?.contains("pending=1") ?? true }
        }
        return true
    }
    private func onlineDisplays() -> [CGDirectDisplayID]? {
        var ids = [CGDirectDisplayID](repeating: 0, count: 32); var count: UInt32 = 0
        let error = CGGetOnlineDisplayList(UInt32(ids.count), &ids, &count)
        guard error == .success else { log("Online displays failed: \(error.rawValue)"); return nil }
        return Array(ids.prefix(Int(count)))
    }
    private func logTopology(_ reason: String) {
        guard let displays = onlineDisplays() else { return }
        let description = displays.map { id -> String in
            let bounds = CGDisplayBounds(id)
            let mode = CGDisplayCopyDisplayMode(id)
            let modeText = mode.map { "logical=\($0.width)x\($0.height) backing=\($0.pixelWidth)x\($0.pixelHeight) hz=\($0.refreshRate)" } ?? "mode unavailable"
            return "mode=(\(modeText)) id=\(id) builtin=\(CGDisplayIsBuiltin(id)) angle=\(CGDisplayRotation(id)) mirror=\(CGDisplayMirrorsDisplay(id)) inMirrorSet=\(CGDisplayIsInMirrorSet(id)) bounds=\(bounds) pixels=\(CGDisplayPixelsWide(id))x\(CGDisplayPixelsHigh(id))"
        }.joined(separator: "; ")
        log("\(reason): \(description)")
    }
    private func extendInternalDisplay(_ internalID: CGDirectDisplayID) -> Bool {
        guard let displays = onlineDisplays(), displays.contains(internalID) else { return false }
        let source = CGDisplayMirrorsDisplay(internalID)
        let master = source == kCGNullDirectDisplay ? internalID : source
        var mirrors = displays.filter { CGDisplayMirrorsDisplay($0) == master }
#if ROTATION_DEBUG
        if mirrors.isEmpty && displays.count == 2 && displays.allSatisfy({ CGDisplayIsInMirrorSet($0) != 0 }) {
            // On this captured two-panel topology both mirror masters reported0.
            // Restrict fallback to the unambiguous two-display case.
            mirrors = displays
            log("Debug two-display mirror fallback: detach both members")
        }
#endif
        guard !mirrors.isEmpty else {
            log("Cannot leave internal mirror set: no mirrored members found")
            return false
        }
        logTopology("Before extending")
        var config: CGDisplayConfigRef?
        let begin = CGBeginDisplayConfiguration(&config)
        guard begin == .success, let transaction = config else {
            log("Begin extended configuration failed: \(begin.rawValue)"); return false
        }
        for display in mirrors {
            let error = CGConfigureDisplayMirrorOfDisplay(transaction, display, kCGNullDirectDisplay)
            guard error == .success else {
                CGCancelDisplayConfiguration(transaction)
                log("Detach mirror id=\(display) failed: \(error.rawValue)"); return false
            }
        }
        // Keep extended mode across later orientation changes and app restarts,
        // just as the existing F1 mirror toggle saves a permanent configuration.
        let error = CGCompleteDisplayConfiguration(transaction, .permanently)
        log("Extended configuration result=\(error.rawValue) members=\(mirrors)")
        logTopology("After extending")
        return error == .success
    }
    private func rotate(_ id: CGDirectDisplayID, to angle: Int32) -> Bool {
        guard let cls = displayClass, let type = cls as? NSObject.Type else { return false }
        let initSelector = NSSelectorFromString("initWithCGSDisplayID:")
        let canSelector = NSSelectorFromString("canChangeOrientation")
        let setSelector = NSSelectorFromString("setOrientation:")
        guard let initMethod = class_getInstanceMethod(cls, initSelector),
              let canMethod = class_getInstanceMethod(cls, canSelector),
              let setMethod = class_getInstanceMethod(cls, setSelector),
              let allocated = type.perform(NSSelectorFromString("alloc"))?.takeUnretainedValue() else { return false }
        typealias InitFn = @convention(c) (AnyObject, Selector, UInt32) -> AnyObject?
        typealias CanFn = @convention(c) (AnyObject, Selector) -> Bool
        typealias SetFn = @convention(c) (AnyObject, Selector, Int32) -> Void
        let initialize = unsafeBitCast(method_getImplementation(initMethod), to: InitFn.self)
        guard let object = initialize(allocated, initSelector, id) else { return false }
        let can = unsafeBitCast(method_getImplementation(canMethod), to: CanFn.self)
        guard can(object, canSelector) else { return false }
        let set = unsafeBitCast(method_getImplementation(setMethod), to: SetFn.self)
        set(object, setSelector, angle)
        return true
    }
    private func log(_ text: String) {
        guard let url = logURL else { return }
        let line = "\(Date()) \(text)\n"
        guard let bytes = line.data(using: .utf8) else { return }
        // Keep persistent diagnostics bounded; no per-sample log spam.
        if let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
           let size = attributes[.size] as? NSNumber, size.intValue > 1_048_576 {
            try? FileManager.default.removeItem(at: url)
        }
        if !FileManager.default.fileExists(atPath: url.path) { FileManager.default.createFile(atPath: url.path, contents: nil, attributes: nil) }
        if let file = FileHandle(forWritingAtPath: url.path) { file.seekToEndOfFile(); file.write(bytes); file.closeFile() }
    }
}
