# IntelISH macOS port

Last updated 2026-10-05.

Target: HP Elite x2 1012 G2, Intel Sunrise Point-LP ISH PCI `8086:9d35`.
Linux reference: `../refs/linux-sensors-camera/linux/drivers/hid/intel-ish-hid/`,
commit a90ee43 (2026-10-04), GPL-2.0-only. Keep upstream reference files untouched.

## Current stage

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
clang++ -std=c++14 -Wall -Wextra -Werror -fsanitize=address,undefined protocol-tests.cpp -o /tmp/ish-protocol-tests
/tmp/ish-protocol-tests
clang++ -std=c++14 -Wall -Wextra -Werror -fsanitize=address,undefined als-tests.cpp -o /tmp/ish-als-tests
/tmp/ish-als-tests test-data/device0-20261005.bin
```

## Power management (0.5.0)

IOService power callbacks serialize through the transport work loop. Sleep cancels polling, disables interrupts and clears host-ready/DMA before PCI power loss. Wake restarts IPC reset, HBM/HID enumeration, descriptor discovery and ALS feature readback. This uses full reinitialization rather than the Linux D0i3 retention path; firmware sleep-state support remains unadvertised. Suspended, WakeCount, PM log lines and fresh ALSControlsVerified expose recovery. Hardware wake verification is pending. No VirtualSMC integration yet.
