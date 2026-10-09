# IntelISH macOS port

Last updated 2026-10-09.

Target: HP Elite x2 1012 G2, Intel Sunrise Point-LP ISH PCI `8086:9d35`.
Linux reference: `../refs/linux-sensors-camera/linux/drivers/hid/intel-ish-hid/`,
commit a90ee43 (2026-10-04), GPL-2.0-only. Keep upstream reference files untouched.

## Current stage (2026-10-08)

Branch `motion-sensors`, 0.7.0 adds accelerometer decoding/control to the existing ALS transport. Accelerometer implementation committed on this branch. Captured device0/report7 has signed32 XYZ at report-inclusive bits152/184/216, exponent−6/unit0, input32/feature229 bytes. Feature readback and raw samples/metadata are exposed in IORegistry; gyro and automatic rotation are not enabled. Hardware sample delivery and cardinal orientation anchors verified; `../tools/accel-probe.py` captures all diagnostics while the user follows pose prompts. Full status, exact EFI backups and undo live in `../context/sensors.md`. Project-local SDKs are described in README.md. Host accel/ALS/protocol sanitizer tests and Debug build pass.

## Standalone rotation app (2026-10-09)

Branch standalone-rotation (base main f31fe3d) adds ISHRotation/, a separate app Xcode project; driver source unchanged. Release app build/policy checks pass; app installed and enabled with old YogaSMCNC rotation disabled. Connected hardware round trip works; unplugged late1x fallback observed. App0.1.1 adds bounded HiDPI preservation, build/selection tests pass; unplugged repeated retest passes. Extra blanking/reannounce follow-up and modern login launch pending. Own README documents dependencies, build, diagnostics and release packaging. Full live status/undo in ../context/rotation.md; controls-only YogaSMC worktree in ../context/development.md. App source committed on standalone-rotation; not pushed.

## Earlier stages (historical)

### ALS 0.4.1

Version 0.4.1 adds ALS report control and decoding after HID discovery.
ALSReport.hpp parses runtime descriptors rather than assuming field offsets.
The captured device-0 descriptor yields report ID 2, feature length 245 bytes,
input length 23 bytes, power field bit 32, reporting bit 8, illuminance bit 152
(width 32, decimal exponent -3, unit 0 interpreted as lux per Linux ALS rules).
Power/reporting array values are derived from usages + logical minimum, both 2.

Sequence: GET_FEATURE, save original bytes, change power/reporting only,
SET_FEATURE over fragmented mailboxes, GET_FEATURE readback, then GET_INPUT.
Report interval, sensitivity and other fields are preserved. One credit covers
all fragments of a message. Valid input is decoded as raw and milli-lux; latest
report/value/count and all feature snapshots are retained in IORegistry.
GET_INPUT polls every second; unsolicited single/list input reports also decode.
No IOHID publication or VirtualSMC/automatic-brightness integration yet.

Interrupts/watchdog run on one workloop; no blocking firmware waits in start.
Setup requests have bounded timers, continuous polling has per-request timeout.
Linux wake gate/PCI bus mastering are used; no host DMA buffers are offered.
Malformed inputs are logged; reported u32 illuminance can exceed the descriptor logical maximum, matching Linux ALS. ALSExceedsDeclaredMaximum records this; transport failures stop host notifications.
Sleep/wake and feature restoration on unload remain unimplemented/untested.

Build and ASan/UBSan tests pass against the captured real descriptor: feature
field preservation, scaling, truncated descriptors and randomized malformed data.
0.4.0 feature controls and input delivery verified; firmware metadata identifies Capella CM32181. Its raw 21685 input exceeded the declared max10000, fixed in 0.4.1 with an exact-packet regression test. Continuous/cover readings await runtime validation. After reboot run
../tools/alslog.sh, expose/cover/uncover during its 30-second capture. Output
saved to ../logs/als-<timestamp>.txt, including IORegistry and kernel diagnostics.

Build:

```sh
xcodebuild -project IntelISH.xcodeproj -target IntelISH -configuration Debug build
```

Uses the existing `../YogaSMC/MacKernelSDK`. Output: `build/Debug/IntelISH.kext`.
No Lilu, VirtualSMC or VoodooI2C dependency in this transport stage.

## Remaining work

Verify feature readback and actual light changes, then integrate VirtualSMC.
Motion shares transport; cameras require a separate IPU3 port.

Protocol/ALS tests:

```sh
clang++ -std=c++14 -Wall -Wextra -Werror -fsanitize=address,undefined tests/protocol-tests.cpp -o /tmp/ish-protocol-tests
/tmp/ish-protocol-tests
clang++ -std=c++14 -Wall -Wextra -Werror -fsanitize=address,undefined tests/als-tests.cpp -o /tmp/ish-als-tests
/tmp/ish-als-tests tests/test-data/device0-20261005.bin
```

## Power management (0.5.0)

IOService power callbacks serialize through the transport work loop. Sleep cancels polling, disables interrupts and clears host-ready/DMA before PCI power loss. Wake restarts IPC reset, HBM/HID enumeration, descriptor discovery and ALS feature readback. This uses full reinitialization rather than the Linux D0i3 retention path; firmware sleep-state support remains unadvertised. Suspended, WakeCount, PM log lines and fresh ALSControlsVerified expose recovery. Hardware wake verification is pending. No VirtualSMC integration yet.

## VirtualSMC light integration (0.6.0)

IntelISH now supplies the nine light/compatibility keys used by upstream SMCLightSensor, after the first valid ISH reading. ALV0 carries big-endian FP18.14 lux (fractional lux retained), valid/high-gain flags and channel0; ALV1 describes no second sensor. AL! host overrides are honored. Atomic cached reads do no transport work in SMC callbacks; sleep/failure invalidates readings. Each report posts SmcEventALSChange after successful plugin submission. IORegistry exposes SMCSubmitted, SMCSubmitResult, SMCLuxFixed, SMCALSNotificationPosted and SMCError. Requires VirtualSMC1.3.8/Lilu1.7.2 before IntelISH. Like upstream, plugin unload is prohibited once keys are published. Automatic brightness/UI behavior needs runtime verification. Upstream reference: acidanthera/VirtualSMC Sensors/SMCLightSensor; BSD license in VirtualSMC-LICENSE.txt.

0.6.1 corrects key identifier byte order with the SDK SMC_MAKE_IDENTIFIER macro;0.6.0 submission succeeded but names were reversed. Compile-time ALV0 identifier assertion guards the representation.
