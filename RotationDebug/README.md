# RotationDebug rotation debugger

Updated 2026-10-09. Command-driven debug app for the HP Elite x2 on Ventura. No accelerometer pose controls orientation. It shares the production IntelISHRotation controller, policy and mode-selection sources using the `ROTATION_DEBUG` build condition. The production app is stopped and Auto-Rotate disabled during debugging; both apps share an instance lock. YogaSMCNC rotation must also remain off.

Build independently (no driver build):

```sh
xcodebuild -project RotationDebug/RotationDebug.xcodeproj -scheme RotationDebug \
  -configuration Release -derivedDataPath RotationDebug/build build
```

Install `RotationDebug/build/Build/Products/Release/RotationDebug.app` in `/Applications`, then launch it. It has a small status-menu indicator and no login registration. Command clients send a validated request to the running GUI app and wait for its reply. Per-launch session IDs prevent replay of stale requests. This keeps the MonitorPanel calls in the installed app's GUI session.

```sh
/Applications/RotationDebug.app/Contents/MacOS/RotationDebug --command 'status'
/Applications/RotationDebug.app/Contents/MacOS/RotationDebug --command 'rotate 90'
/Applications/RotationDebug.app/Contents/MacOS/RotationDebug --command 'repair off'
```

Commands: `rotate 0/90/180/270`, `status`, `modes`, `native`, `hidpi`, `hidpi save`, `repair on/off`, `quit`. A rotation reply confirms the request returned; actual completion comes from observed angles/modes in the timeline. Portrait leaves mirroring using the production auto-extend route. `native` and `hidpi` select actual publicly available modes. `hidpi save` also permanently stores that mode through a CoreGraphics display-configuration transaction, even if it is already selected. Repair now saves its correction too. Repair defaults off, allowing observation without the production scaling correction; turning it on uses the same bounded HiDPI preservation. No simulated sensor values are injected into the kext.

Logs: `~/Library/Logs/RotationDebug/{rotation.log,timeline.jsonl}`. An independent sampler records logical/backing dimensions, rotation, mirroring, refresh, mode IDs/flags and framebuffer status every200ms, including while the rotation call is running. Command begin/end markers, timestamps and inventories share the timeline. Sampling does not directly measure visible panel blanking.

From IntelISH's root, run a repeatable software test against whatever monitors are currently attached:

```sh
python3 RotationDebug/run-tests.py --label connected --repair off --baseline hidpi \
  --angles 90,0,270,0 --settle 12 --output /path/to/new-test-directory
```

The runner saves responses and only that run's telemetry, and restores the starting angle. Reconnect/disconnect is the user's physical step; the agent runs all orientation tests and analysis. Do not reset WindowServer display preferences merely to reproduce a cold first rotation. The required guards/HiDPI/scaler patches remain in FBReannounce, which retains separate event history for correlation.

Undo: send `quit` to RotationDebug; restore the saved IntelISHRotation AutoRotate preference and reopen the production app. The setup snapshot path is recorded in the workspace `tools/intelishv2-backup.txt`. This app and the runner do not change EFI, publish releases or register login items. GPL-2.0-only under the repository LICENSE; source origin is the HP YogaSMC fork as credited in IntelISHRotation/README.md.
