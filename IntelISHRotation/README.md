# IntelISHRotation

Updated 2026-10-09. A small menu-bar app for the HP Elite x2 1012 G2 on macOS Ventura 13.7.8. Reads IntelISH accelerometer samples and rotates the internal display without depending on YogaSMC.kext or YogaSMCNC. Standalone connected portrait/landscape rotation is user-confirmed. Unplugged rotation initially reaches HiDPI but later falls back to 1×; version0.1.1 restores it successfully in repeated unplugged rotation tests. The first retest needed two repairs after delayed resets; subsequent orientations retained HiDPI. Version0.1.2 saves the repaired HiDPI choice using a permanent display configuration; connected and unplugged command-driven tests retain HiDPI with repair disabled after the corrected selections are saved; unplugged90°/270° tests also pass after reboot. Extra post-rotation blanking remains a follow-up. Login startup remains to be tested.

The orientation policy, MonitorPanel rotation and mirror-to-extended transition come from the tested YogaSMC HP fork at `08524b9`. The new app shell supplies its own menu, preferences, bounded logs and Ventura `SMAppService.mainApp` login registration. IntelISH itself collects sensor data without this app.

## Requirements

- IntelISH 0.7.0: sensor transport, ambient light and accelerometer samples.
- FBReannounce 0.2.3: both SkyLight guards, framebuffer reannounce, rotated scaling and portrait HiDPI eligibility.
- The patched Lilu runtime from `yjmd2222/Lilu`, branch `x2g2-userpatch`, revision `57bfe9ce4c47e10d1c5874a72d1c6d7a7a76bcd9`, version 1.7.3. Stock Lilu does not provide the tested shared-cache patches.
- Existing IntelISH prerequisites, including VirtualSMC, remain required. Preserve working input/audio kexts.

The private rotation route is enabled only on Ventura. Other macOS versions show an unavailable status. Sensor layout and mounting are specific to the tested HP. The tested display setup retains the existing display override; removing it has not been tested.

## Build and use

```sh
xcodebuild -project IntelISHRotation/IntelISHRotation.xcodeproj -scheme IntelISHRotation \
  -configuration Release -derivedDataPath IntelISHRotation/build build
```

Run from the IntelISH repository. Output: `IntelISHRotation/build/Build/Products/Release/IntelISHRotation.app`. This app target builds no kext and needs no kernel SDK. Install the app in `/Applications` before enabling Start at Login.

Auto-Rotate and Rotation Lock default off. The app uses its own `org.yjmd2222.ISHRotation` preferences. Enable Auto-Rotate from its menu. Stable edge poses are held for 0.6 seconds; flat, diagonal and excessive acceleration retain the current angle. Portrait leaves mirroring for extended mode; returning to landscape keeps extended mode. Only the internal display rotates.

Version0.1.2 remembers the logical edges of the current HiDPI mode. For 12 seconds after startup, orientation or display-topology changes, it monitors mode changes, waits for the FBReannounce pending notification to clear and for the mode to settle, then restores and permanently saves a matching HiDPI mode if macOS fell back to 1×. This replaces the saved native portrait choice instead of only changing the current mode. It preserves orientation and prefers the current refresh rate. Repair is limited to two attempts per transition; it skips mirror sets and does not continually override a later manual 1× selection.

During migration, turn Auto-Rotate off in the old YogaSMCNC and restart it before enabling this app. IntelISHRotation pauses if a running legacy YogaSMCNC still has Auto-Rotate enabled. The controls-only YogaSMC build declares `ISHRotationControllerEmbedded=false` and can coexist normally. A process lock prevents two active IntelISHRotation instances. Quitting IntelISHRotation stops automatic rotation while preserving the last display angle.

Start at Login registers this app directly using the modern Ventura API. If macOS requests approval, the menu opens Login Items settings. No legacy helper or LaunchAgent is installed.

## Diagnostics and tests

Logs: `~/Library/Logs/IntelISHRotation/{rotation,login}.log`. Rotation logs include topology, observed/requested angles and readiness. Read-only diagnostics never enable rotation:

```sh
/Applications/IntelISHRotation.app/Contents/MacOS/IntelISHRotation --diagnose
swiftc IntelISHRotation/Sources/RotationPolicy.swift IntelISHRotation/Sources/HiDPIModePolicy.swift IntelISHRotation/tests/main.swift \
  -o /tmp/ishrotation-policy-test
/tmp/ishrotation-policy-test
```

Existing IntelISH IORegistry diagnostics and FBReannounce boot patch messages still apply. A hardware test should capture sensor/framebuffer state, both app logs, current logical/backing display modes and WindowServer PID before and after a portrait/landscape round trip.

## Release packaging

Keep the kext and app Xcode projects separate in this repository. Offer IntelISH-only downloads and a rotation bundle through IntelISH releases. Bundle `IntelISH.kext`, `FBReannounce.kext`, `IntelISHRotation.app`, installation notes and licenses. Keep the required patched Lilu revision explicit; do not silently replace an existing Lilu installation.

`package.py` assembles supplied build products and writes a component/version/hash manifest. Use artifacts built from the listed source revisions. It does not build drivers, edit EFI, install software or publish a release. A published release should also record the IntelISH/app source commit after this work is committed. The initial app build is ad-hoc signed, not notarized.

```sh
python3 IntelISHRotation/package.py --app IntelISHRotation/build/Build/Products/Release/IntelISHRotation.app \
  --intelish build/Release/IntelISH.kext --fbreannounce /path/to/FBReannounce.kext \
  --output IntelISHRotation/build/rotation-package
```

## Credits

GPL-2.0-only, under the repository’s LICENSE. Rotation code and modern login approach originate in yjmd2222’s HP YogaSMC fork. YogaSMC is by Zhen-zen and contributors. IntelISH is the HP port of Linux’s ISH/HID sensor transport. FBReannounce and the required Lilu fork retain their own credits, including Acidanthera/vit9696 and joevt’s shared-cache work. See each component’s license and documentation.

The app was renamed from ISHRotation to IntelISHRotation. Its bundle ID remains `org.yjmd2222.ISHRotation` so existing preferences and login registration retain the same identity. The shared instance-lock directory remains `Application Support/ISHRotation`; current logs use `Library/Logs/IntelISHRotation`. RotationDebug is a separate development app and is excluded from component release packages.
