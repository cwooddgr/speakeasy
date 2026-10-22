# Speakeasy

Menu-bar helper for macOS 27 that stops built-in Dictation when Return is pressed, then lets the Return through. Tier 3, personal tool (started 2026-10-21).

## Commands
- `./build.sh` builds `build/Speakeasy.app`, signs it with the DGR Labs Developer ID, installs it to `~/Applications`, and relaunches it.
- `./build.sh --no-install` builds and signs only.
- `swiftc -O probe/probe.swift -o probe/probe` builds the diagnostic probe (window and mic-input logger).

## How it works
- Dictation state comes from DictationIM's unified-log line `Keyboard Dictation: Update Dictation State: N` (1 = listening, 0 = stopped), read through a `/usr/bin/log stream` child process. This wording is undocumented; if a macOS update changes it, the helper goes inert and Return behaves normally.
- A `CGEventTap` swallows Return or keypad Enter while listening, posts Escape (Apple's documented stop key, which keeps the dictated text), waits up to 0.4 s for state 0, then replays the key with its original modifiers. Synthetic events carry `eventSourceUserData = 0x5350_4B45`.
- Needs Accessibility permission. It's signed with a stable Developer ID, so the grant survives rebuilds.

## Findings (2026-10-21 probe, macOS 27.0.1)
- No new process takes mic input during Dictation (`corespeechd` already holds it), so mic-in-use is not a usable signal.
- The in-app dictation bubble (an 84×77 window at layer 3, owned by the focused app) hides mid-session, so it's unreliable.
- The Window Server `StatusIndicator` lags the stop by about 1 s.

Status: v1 built and installed 2026-10-22; awaiting first real-use test.
