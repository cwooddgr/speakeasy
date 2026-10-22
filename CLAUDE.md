# Speakeasy

Menu-bar helper for macOS 27 that stops built-in Dictation when Return is pressed, then lets the Return through. Tier 2, listed under "Also from the Labs" on dgrlabs.co (decided-by-user 2026-10-22). Public repo, MIT. Started 2026-10-21.

## Commands
- `./build.sh` builds `build/Speakeasy.app`, signs it with the DGR Labs Developer ID, installs it to `/Applications`, and relaunches it.
- `./build.sh --no-install` builds and signs only.
- The signing identity lives in the untracked `.signing-identity` file (our Developer ID name, one line). If the file is missing, `build.sh` signs ad-hoc and the Accessibility grant breaks on every rebuild.
- The app icon is `Speakeasy.icon` (Icon Composer format, hand-written `icon.json` plus SVG layers). `build.sh` compiles it with `actool` into `Assets.car` and `Speakeasy.icns`. To preview it, run `ictool` from `Icon Composer.app/Contents/Executables` with `--export-image`.
- `swiftc -O probe/probe.swift -o probe/probe` builds the diagnostic probe (window and mic-input logger).

## Architecture
- `Sources/main.swift` is the whole app: `DictationMonitor` follows DictationIM's unified-log lines through `/usr/bin/log stream`; `ReturnInterceptor` is a `CGEventTap` that, on Return while listening, presses the front app's Edit > Stop Dictation (`AXIdentifier` `stopDictation:`) and replays the key once the session reports its outcome. The fallback is Escape. The menu-bar UI and login item live in `AppDelegate`.
- Mechanism detail, log signals, and probe findings: `docs/dictation-findings.md`. Decisions: `docs/decisions.md`. Status history: `docs/status.md`.

## Standing rules
- Never commit the signing identity; it stays in `.signing-identity` (decided-by-user 2026-10-22, see `docs/decisions.md`).
- The repo is public: audit for private data before every push (decided-by-user 2026-10-22).

Status: v1.0 installed at `/Applications/Speakeasy.app` and working in TextEdit; public at github.com/cwooddgr/speakeasy (MIT); dgrlabs.co listing handed to the dgrlabs-co session 2026-10-22, not confirmed live.
