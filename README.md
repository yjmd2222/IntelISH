# IntelISH

macOS driver for the Intel Integrated Sensor Hub on the HP Elite x2 1012 G2 (PCI `8086:9d35`). Reads the ambient light sensor through ISHTP/HID and publishes lux through VirtualSMC for automatic brightness.

## Build

Requires Xcode, MacKernelSDK, Lilu 1.7.2 and VirtualSMC 1.3.8 SDK resources. Place build dependencies beside the Xcode project:

```
IntelISH/
  MacKernelSDK/       # Headers/ and Library/x86_64/
  Lilu.kext/         # Contents/Resources/Headers/
  VirtualSMC.kext/   # Contents/Resources/VirtualSMCSDK/
  IntelISH.xcodeproj/
```

Dependencies are ignored by Git. Use the corresponding Acidanthera repositories/releases; Lilu and VirtualSMC SDK headers are included in their development kext bundles. Existing workspace dependencies have been copied locally so this project no longer depends on YogaSMC's directory.

```sh
xcodebuild -project IntelISH.xcodeproj -target IntelISH -configuration Debug build
```

Use `-configuration Release` for a release build. Outputs are in `build/Debug/` and `build/Release/`. Live HID descriptor properties and hex dumps are Debug-only; descriptor parsing remains enabled in both.

Sources and Info.plist live in `IntelISH/` (Acidanthera layout: project at the root, inner folder named after it). Standalone tests and captured fixtures live in `tests/` and are excluded from both kext builds.

 Load Lilu and VirtualSMC before IntelISH in OpenCore. Disable SMCLightSensor to avoid competing light keys; keep the workspace's original SSDT-ALS0.

## Scope

Ambient light and transport recovery are implemented. Version 0.7.0 adds descriptor-driven accelerometer feature setup and signed X/Y/Z reports in IORegistry (hardware samples and orientation anchors verified). Gyroscope decoding is next; camera capture is handled by a separate project. Development history and test commands are in `AGENTS.md` and the workspace sensor context.

## Optional display rotation app

[IntelISHRotation](IntelISHRotation/README.md) is a separate Xcode app project in this repository. It reads accelerometer samples directly, offers Auto-Rotate/Rotation Lock and modern login startup, and requires FBReannounce0.2.3 plus the pinned patched Lilu runtime. YogaSMC is not required. Connected and unplugged portrait HiDPI have passed command-driven tests, including unplugged reboot persistence. IntelISH-only users do not need the app. Rotation bundles can be assembled using the documented packaging script; this does not publish a release.

[RotationDebug](RotationDebug/README.md) is the development-only command-driven rotation tool. It is built separately and is not included in release packages.
