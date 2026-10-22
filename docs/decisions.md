# Decisions

> **Author:** Claude Code (coder)
> **Date:** 2026-10-22
> **Status:** decided-by-user
Charlie chose to build a probe first and pick the Dictation signal from evidence (option a, 2026-10-21).

> **Author:** Claude Code (coder)
> **Date:** 2026-10-22
> **Status:** decided-by-user
Speakeasy is a menu-bar app with an icon, not an invisible background agent (option a).

> **Author:** Claude Code (coder)
> **Date:** 2026-10-22
> **Status:** proposed-by-agent
I chose to stop Dictation with the Edit > Stop Dictation menu item rather than Escape, because Escape cancels and drops pending audio (see `dictation-findings.md`). Charlie confirmed the result works ("works great").

> **Author:** Claude Code (coder)
> **Date:** 2026-10-22
> **Status:** decided-by-user
The repo is public at github.com/cwooddgr/speakeasy under the MIT license, copyright DGR Labs, LLC. Charlie asked for public visibility and the MIT license; I chose DGR Labs as the holder to match the app's copyright line.

> **Author:** Claude Code (coder)
> **Date:** 2026-10-22
> **Status:** decided-by-user
The signing identity name is kept out of the repo (in the untracked `.signing-identity`), and the history was rewritten and force-pushed to remove it from older commits. Charlie asked for both ("move it", then option b). He declined asking GitHub Support to purge cached old commits ("skip it").

> **Author:** Claude Code (coder)
> **Date:** 2026-10-22
> **Status:** decided-by-user
dgrlabs.co placement is "Also from the Labs" (Tier 2).

> **Author:** Claude Code (coder)
> **Date:** 2026-10-22
> **Status:** proposed-by-agent
I chose ad-hoc signing as the fallback so strangers can build, and `/Applications` as the install location after Charlie couldn't find the app in `~/Applications`.
