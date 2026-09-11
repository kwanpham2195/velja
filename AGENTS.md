# AGENTS.md

Velja: macOS menu bar browser picker. SwiftPM, Swift 6 language mode, macOS 14+. Read README.md for behavior.

## Layout

- `Sources/VeljaCore`: every routing decision (matching, rules, router, link cleanup, app link rewrites, profile parsing, settings files). Foundation only. New routing behavior goes here, with tests in `Tests/VeljaCoreTests`.
- `Sources/Velja`: AppKit/SwiftUI shell. `IncomingLinkHandler` is the pipeline; keep it a thin sequence of calls.
- `docs/CHANGELOG.md`: changelog. `Resources/Info.plist` has `__VERSION__`/`__BUILD_NUMBER__` placeholders filled by `scripts/build-app.sh`.

## Commands

- Tests are end-to-end first: `make e2e` (real app + Launch Services + `e2e/FakeBrowser` recorder). New user-visible routing behavior gets an e2e case in `scripts/e2e.sh`; unit tests stay few and cover only risky pure logic (the user asked for this).
- Unit tests: `make test`. Bare `swift test` fails with only Command Line Tools (no `Testing` module); `scripts/test.sh` adds the paths and disables cross-import overlays.
- Pre-handoff gate: `swift build` with zero warnings, `make test`, `make e2e`, `make snapshots` and look at the PNGs.
- `make e2e` refuses to run while another Velja is running; quit it first.
- UI check without screen recording permission: `make snapshots` → `/tmp/velja-snapshots/*.png`. Uses a temp settings folder.

## Live testing gotchas

- `open -a` needs an absolute path: `open -a "$PWD/build/Velja.app" 'https://example.com'`.
- Logs: `/usr/bin/log stream --level info --predicate 'subsystem == "com.kwanpham.Velja"'`. Plain `log` is a zsh builtin.
- Manual live runs read and write the real `~/Library/Application Support/Velja/Settings.json`. Start the binary with `VELJA_SUPPORT_DIRECTORY=/tmp/x build/Velja.app/Contents/MacOS/Velja` to isolate them, as `scripts/e2e.sh` does.
- macOS activates Velja when it delivers a link, so `frontmostApplication` is Velja. Use `PreviousAppTracker` for "the app the user was in".
- Status items on macOS 26 are hosted by Control Center; they never show in `CGWindowListCopyWindowInfo`.
- Launch Services never returns apps registered from `/tmp` (`urlForApplication` is nil), so test fixture apps live under `build/`. Unregister them with `lsregister -u` before deleting.
- Process paths use the on-disk case (`/Users/…/Work/…`) even when `$PWD` differs; match them with `pgrep -if`/`pkill -if`.
- Sources of links sent with `open` fall back to the frontmost/previous app, so e2e cases that depend on the source app scope their rule with a domain too.

## Rules

- Open web links only with an explicit app URL (`LinkOpener`). `NSWorkspace.open(url)` hands the link back to Velja when it is the default browser.
- `velja:open` input is untrusted (web pages can trigger it): http/https links only, and `app` must be an installed browser target.
- SwiftUI string literals are Markdown: use `Text(verbatim:)` for copy containing `www.`, `*`, or `_`.
- App link rewrites need a public reference (Finicky wiki or vendor docs); unverified schemes stay out.
