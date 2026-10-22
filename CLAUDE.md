# Speakeasy

Menu-bar helper for macOS 27 that stops built-in Dictation when Return is pressed, then lets the Return through. Tier 2, listed under "Also from the Labs" on dgrlabs.co (decided-by-user 2026-10-22). Public repo, MIT. Started 2026-10-21.

## Commands
- `./build.sh` builds `build/Speakeasy.app`, signs it with the DGR Labs Developer ID, installs it to `~/Applications`, and relaunches it.
- `./build.sh --no-install` builds and signs only.
- The signing identity lives in the untracked `.signing-identity` file (our Developer ID name, one line). If the file is missing, `build.sh` signs ad-hoc and the Accessibility grant breaks on every rebuild.
- The app icon is `Speakeasy.icon` (Icon Composer format, hand-written `icon.json` plus SVG layers). `build.sh` compiles it with `actool` into `Assets.car` and `Speakeasy.icns`. To preview it, run `ictool` from `Icon Composer.app/Contents/Executables` with `--export-image`.
- `swiftc -O probe/probe.swift -o probe/probe` builds the diagnostic probe (window and mic-input logger).

## How it works
- Dictation state comes from DictationIM's unified-log lines, read through a `/usr/bin/log stream` child process: `Keyboard Dictation: Update Dictation State: N` (1 = listening, 2 = stopping, 0 = stopped) and `+[AFAggregator logDictation<Outcome>]` (session finished). This wording is undocumented; if a macOS update changes it, the helper goes inert and Return behaves normally.
- A `CGEventTap` swallows Return or keypad Enter while listening, then presses the front app's Edit > Stop Dictation menu item through Accessibility (`AXIdentifier` `stopDictation:`, locale-independent). That's the same "stop listening" path the mic key uses, so pending audio finishes transcribing. The helper waits for the session outcome (up to 3 s), then replays the key with its original modifiers. Synthetic events carry `eventSourceUserData = 0x5350_4B45`.
- Fallback for apps without that menu item: Escape, then wait for state 0. Escape ends the session as Cancelled and drops audio still being processed.
- A Return delivered during state 2 makes Dictation resume listening, which is why we wait for the full stop.
- Needs Accessibility permission. It's signed with a stable Developer ID, so the grant survives rebuilds.

## Findings (2026-10-21 probe, macOS 27.0.1)
- No new process takes mic input during Dictation (`corespeechd` already holds it), so mic-in-use is not a usable signal.
- The in-app dictation bubble (an 84×77 window at layer 3, owned by the focused app) hides mid-session, so it's unreliable.
- The Window Server `StatusIndicator` lags the stop by about 1 s.
- Escape logs `logDictationCancelled`; the mic key and the Stop Dictation menu item log `stop listening` and then `logDictationSucceeded` 100–400 ms later.
- The menu item's identifier is `startDictation:` when idle and `stopDictation:` while active. After a silent session that fails (error 1110), it can stick on "Cancel Dictation" until pressed.

Status: v1 working in TextEdit (Charlie confirmed 2026-10-22); not yet tried in other apps.
