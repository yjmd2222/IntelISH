# IntelISH

macOS driver for the Intel Integrated Sensor Hub on the HP Elite x2 1012 G2 (PCI `8086:9d35`). It reads the ambient light sensor and publishes lux through VirtualSMC for automatic brightness, and configures the accelerometer and exposes signed X/Y/Z samples and sensor metadata in IORegistry. IntelISH reads the accelerometer; YogaSMC can use those readings to rotate the display. On the HP Elite x2 1012 G2 running Ventura 13.7.8, [FBReannounce](https://github.com/yjmd2222/fbreannounce) is a separate companion kext that helps macOS recognize the built-in display after rotation. Gyroscope decoding is not implemented.

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

Ambient light, transport recovery, and descriptor-driven accelerometer setup/reporting are implemented. Hardware accelerometer samples and orientation anchors have been verified. Camera capture is handled by a separate project. Development history and test commands are in `AGENTS.md` and the workspace sensor context.
