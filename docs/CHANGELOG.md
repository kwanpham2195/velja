# Changelog

## Unreleased

The first version of Velja, a browser picker for macOS that routes every clicked link to the right browser, browser profile, or desktop app.

### What's new

- Add the browser picker, which opens next to the pointer and supports number keys, background opening, copying the link, and ⌘-click to always open a domain in a browser.
- Add rules that match links by domain (including international domains), prefix, wildcard, or regex and by the app the link was clicked in, and send them to a browser, a Chromium profile, or the picker.
- Add Chromium profile support for Chrome, Edge, Brave, Vivaldi, and Chromium, with one picker entry per profile.
- Add app links for Zoom, Microsoft Teams, Figma, Spotify, Discord, and Apple Music (off by default); a link that comes from the app itself goes to your browser instead.
- Add the primary browser and the alternative browser, which is used while the Fn (Globe) key is held.
- Add optional tracking parameter removal and short link expansion that contacts only the link shortener.
- Add the `velja:open` URL scheme, which accepts only web links and installed browsers, plus the Open Link with Velja service and Open Link from Clipboard in the menu bar.
- Add rule import and export, optional link history with the detected source app, and launch at login.
