# Dictation findings

> **Author:** Claude Code (coder)
> **Date:** 2026-10-22
> **Status:** proposed-by-agent (observed on macOS 27.0.1, build 26A434)

## Signals we use
- DictationIM (`/System/Library/Input Methods/DictationIM.app`, a launchd service that stays running between sessions) logs `Keyboard Dictation: Update Dictation State: N`, where 1 = listening, 2 = stopping, and 0 = stopped.
- At the end of a session it logs `+[AFAggregator logDictation<Outcome>]`: `Succeeded` after the mic key or Stop Dictation menu item, `Cancelled` after Escape, and `FailedWithError:` (code 1110) after a silent session.
- `/usr/bin/log stream` delivers lines through a pipe in about 1–2 ms with no buffering. In zsh, `log` is a builtin, so always call `/usr/bin/log`.

## How we stop Dictation
- The mic key and Edit > Stop Dictation both go through "stop listening", which finishes transcribing pending audio and then logs `Succeeded` 100–400 ms after state 0.
- Escape ("pause dictation for user interaction", then `Cancelled`) commits text already on screen but drops audio still being processed. Charlie saw trailing words lost on 2026-10-22.
- The menu item's `AXIdentifier` is `startDictation:` when idle and `stopDictation:` while active; the title is localized. Pressing it with AX takes about 25 ms. Seen in TextEdit, Terminal, Safari, and Messages.
- A Return delivered during state 2 makes Dictation resume listening (2 → 1 about 0.5 s later), so Speakeasy waits for the session outcome before replaying the key.
- Any key press while listening logs "pause dictation for user interaction" and briefly enters state 2. That's the built-in "type while dictating" behavior.

## Signals we rejected (2026-10-21 probe, `probe/probe.swift`)
- Mic input per process: no new process takes the mic during Dictation, because `corespeechd` already holds it.
- The in-app dictation bubble (84×77 window at layer 3, owned by the focused app) hides mid-session.
- The Window Server `StatusIndicator` window lags the stop by about 1 s.

## Testing gotchas
- Synthetic Return events posted from a Terminal-built CLI didn't reach Speakeasy's tap in our test; test with real key presses. The cause wasn't confirmed.
- Silent test sessions can leave the menu item stuck on "Cancel Dictation" (still `stopDictation:`) after state 0. Pressing it once resets it.
- Starting Dictation via System Events "click menu item" is flaky right after `activate`. Pressing the item through AX by identifier works reliably.
