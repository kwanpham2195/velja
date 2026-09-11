# Velja

Velja is a browser picker for macOS. You make it your default browser, and it sends each link you click to the right browser, browser profile, or desktop app. When no rule applies, it shows a small picker next to the pointer so you can choose.

This project is an independent, open implementation of the idea behind Sindre Sorhus's [Velja](https://sindresorhus.com/velja). It is not affiliated with that app and uses its own bundle identifier (`com.kwanpham.Velja`).

## Requirements

- macOS 14 or later
- Swift 6 toolchain. The Xcode Command Line Tools are enough; Xcode is optional.

## Build and install

```sh
make app       # builds build/Velja.app (release, signed ad hoc)
make install   # copies it to /Applications, registers it, and opens it
```

On first launch, Velja opens its settings window. Click **Set Velja as Default Browser…** and confirm the macOS dialog. You can also pick Velja in System Settings > Desktop & Dock > Default web browser. Velja only sees links while it is the default browser.

To install somewhere else, pass `INSTALL_DIR`:

```sh
make install INSTALL_DIR="$HOME/Applications"
```

## How a link is routed

Velja checks these in order and stops at the first one that applies:

1. **Fn (Globe) key.** Holding Fn while clicking a link sends it to the alternative browser and skips everything below.
2. **App links.** Links such as Zoom meetings open in their desktop app when it's installed.
3. **Rules**, from top to bottom.
4. **Primary browser.** This is either a fixed browser or the browser picker (the default).

If a rule or setting points at a browser or profile that's no longer installed, Velja shows the picker instead of losing the link.

## Browser picker

The picker lists every installed app that opens web links. Browsers with several Chromium profiles (Chrome, Edge, Brave, Vivaldi, Chromium) get one entry per profile. You can reorder and hide entries in Settings > Browsers.

| Key | Action |
| --- | --- |
| Return or Space | Open in the highlighted browser |
| 1–9 | Open in that browser |
| ↑ ↓, Tab, Shift-Tab | Move the highlight |
| Control or Shift with Return or a number, or Shift-click | Open in the background |
| ⌘-Return or ⌘-click | Open, and add a rule that always opens this domain in that browser |
| ⌘C | Copy the link |
| Esc, or a click outside | Cancel |

Right-click or Control-click an entry for the same actions. The picker also closes when you switch to another app.

## Rules

A rule sends matching links to a browser, a browser profile, or the picker. A link matches when it satisfies any of the rule's URL patterns and comes from any of its source apps. Leave one side empty to match on the other alone. For example, a rule with the source app Slack and no URL patterns catches every link clicked in Slack.

| Pattern type | Example | Matches |
| --- | --- | --- |
| Domain | `atlassian.net` | `acme.atlassian.net/browse/ABC-1`, and every other subdomain. International domains such as `bücher.de` work too. |
| Prefix | `github.com/acme/` | Links that start with this text, ignoring the scheme, any user name, and a leading `www.` |
| Wildcard | `*.atlassian.net/browse/*` | The whole link, where `*` stands for any text |
| Regex | `/(issues\|pull)/\d+$` | Any link where the expression finds a match, case-insensitively |

A prefix is plain text, so `github.com` also matches `github.com.example.net`. End a prefix with `/`, or use a domain pattern, when that matters. The rule editor has a test field that checks a link against the patterns as you type. Rules can be exported to a JSON file and imported on another Mac from Settings > Rules.

## App links

Each app link applies only when its app is installed. All of them are on by default except Apple Music, because Music is installed on every Mac. Turn them on or off in Settings > App Links.

| App | Links | Opens as |
| --- | --- | --- |
| Zoom | `zoom.us/j/<meeting>` on any Zoom subdomain | `zoommtg://<same host>/join?action=join&confno=…`, keeping `pwd`, `tk`, and `uname` |
| Microsoft Teams | `teams.microsoft.com/l/…` | `msteams://teams.microsoft.com/l/…` |
| Figma | Files, designs, boards, prototypes, and slides on `figma.com` | The web link, in Figma |
| Spotify | `open.spotify.com/…` | The web link, in Spotify |
| Discord | `discord.com/channels/…` | `discord://discord.com/channels/…` |
| Apple Music | `music.apple.com/…` | `itmss://music.apple.com/…`, in Music |

App links are checked before rules, so a rule like "everything from Slack opens in Chrome" still sends Zoom links to Zoom. A link that comes from the app itself, such as Zoom opening one of its own web pages, goes to your browser instead of back to Zoom.

## Link cleanup

Two options in Settings > General change links before they're routed. Both are off by default.

**Remove tracking parameters** strips parameters such as `utm_source`, `fbclid`, `gclid`, and `mc_eid` from every site. It also strips site-specific ones such as `si` on YouTube and Spotify and `s` and `t` on X. Other parameters and the fragment stay exactly as they were. For example, `https://foo.com/?utm_source=x&page=2` becomes `https://foo.com/?page=2`.

**Expand short links** follows redirects of known link shorteners (bit.ly, t.co, tinyurl.com, and others) before routing, so rules see the real site. Velja sends a cookie-less request to the shortener only. It stops at the first redirect that leaves the shortener, so the destination site is never contacted, and it gives up after three seconds.

## Opening links through Velja

Any script or app can send a link through Velja with a `velja:open` URL:

```sh
# Route the link with your rules
open "velja:open?url=https%3A%2F%2Fgithub.com%2Fapple%2Fswift"

# Always show the picker
open "velja:open?url=https%3A%2F%2Fgithub.com&prompt"

# Open in a specific browser and profile
open "velja:open?url=https%3A%2F%2Fgithub.com&app=com.google.Chrome&profile=Profile%201"
```

The `url` value must be a percent-encoded http or https link. `app` must name an installed browser; any other app shows the picker instead. Because web pages can trigger these URLs, Velja never opens local files or arbitrary apps from them.

Velja also adds an **Open Link with Velja** item to the Services menu for selected text, and the menu bar icon has **Open Link from Clipboard**.

## Settings, history, and logs

Velja stores its settings in `~/Library/Application Support/Velja/Settings.json`. If that file can't be read, Velja renames it to `Settings.unreadable-<timestamp>.json`, starts with defaults, and says so in Settings > General.

Link history is off by default. When you turn it on, Velja keeps the last 200 links in `History.json` next to the settings, with the source app it detected and where each link opened. This is the quickest way to find the bundle identifier to use in a source app rule. Turning history off deletes it.

Velja logs routing decisions to the unified log:

```sh
log stream --level info --predicate 'subsystem == "com.kwanpham.Velja"'
```

Links show as `<private>` in the log. The decision, target browser, and source app are logged in full.

## Limitations

- Velja can't see links you click inside a browser, because the browser opens those itself.
- Firefox, Safari, and Arc profiles aren't supported. Those browsers still work as plain entries.
- The source app comes from the process that asked macOS to open the link. When that's a command-line tool such as `open` in a terminal, Velja uses the app you were in, which is usually the terminal.
- Holding Fn while pressing arrow or function keys also sets the Fn flag, so avoid that combination while clicking a link.

## Development

```sh
make e2e        # end-to-end tests against the real app
make test       # a small set of unit tests for the riskiest routing logic
make build      # debug build
make run        # build the app bundle and open it
make snapshots  # render every settings tab and the picker to /tmp/velja-snapshots
```

The end-to-end suite is the main safety net. It builds `Velja.app`, starts it with a temporary settings folder, and sends it links through Launch Services with `open`, the same path a clicked link takes. The links go to a fake browser (`e2e/FakeBrowser`) that records every link and launch argument it receives, including Chromium-style `--profile-directory` launches. No real browser opens, and your real settings are never touched. Quit any running Velja before you start the suite. Two of its links end in the browser picker, which stays on screen until the run finishes.

The suite relies on two environment variables that only take effect when Velja is started with them:

| Variable | Effect |
| --- | --- |
| `VELJA_SUPPORT_DIRECTORY` | Folder for `Settings.json` and `History.json` instead of `~/Library/Application Support/Velja` |
| `VELJA_CHROMIUM_USER_DATA_DIRECTORIES` | Extra Chromium-style browsers, as `bundle.id=/path/to/user-data;other.id=/path`. Velja reads profiles from `Local State` in each folder. |

`make test` works with only the Command Line Tools: `scripts/test.sh` adds the Swift Testing framework and plugin paths that SwiftPM can't find on its own there.

The code is split into two targets. `VeljaCore` holds everything that decides where a link goes (matching, rules, routing, tracking parameter cleanup, app link rewrites, profile parsing, settings files) and has no AppKit dependency. `Velja` is the AppKit and SwiftUI app: Apple event handling, the picker panel, the menu bar item, and the settings window. `make snapshots` renders the UI to PNG files without screen recording permission; it uses a temporary settings folder and never touches your real settings.

The app icon is drawn by `scripts/generate-app-icon.swift`. Run `make icon` to regenerate `Resources/AppIcon.icns`.
