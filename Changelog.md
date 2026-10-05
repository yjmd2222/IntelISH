IntelISH Changelog
==================

#### v0.6.1
- Fixed VirtualSMC key identifier byte order (SMC_MAKE_IDENTIFIER)
- Moved sources into `IntelISH/`, tests into `tests/`, dependencies to project-local paths
- Added Release configuration; Debug keeps HID descriptor registry dumps
- Bundled `VirtualSMC-LICENSE.txt` in the kext

#### v0.6.0
- Added VirtualSMC ambient light keys (ALV0 and compatibility keys) with change notifications

#### v0.5.0
- Added sleep/wake handling: full IPC/HBM/HID reinitialization on wake

#### v0.4.1
- Fixed illuminance values above the descriptor's declared maximum

#### v0.4.0
- Added ALS feature control and report decoding from runtime HID descriptors

#### Earlier
- ISH PCI/IPC transport, ISHTP/HBM and HID client discovery (initial port of the Linux driver)
