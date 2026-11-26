# Mica

A native macOS browser for development, inspired by Search's compact interface. AppKit draws the sidebar, address bar, history/search overlay, extension menu, and start page. Page-only CEF Views supply Chromium and Chrome DevTools, without a second browser toolbar or tab strip. There is no Electron, Node runtime, or web-rendered browser interface.

[Download Mica for macOS](https://github.com/martinrisseeuw/mica-releases/releases/latest) · [Report an issue](https://github.com/martinrisseeuw/mica/issues) · [MIT license](LICENSE)

This repository contains Mica's source code. Signed, notarized installers and the
automatic-update feed are published separately in
[mica-releases](https://github.com/martinrisseeuw/mica-releases).

## Run

Open `dist/Mica.app`. This build targets **Apple Silicon Macs running macOS 13 or later**. The ordinary build is a local development app. Use the release script below to produce a signed, notarized distribution.

```sh
open dist/Mica.app
```

## Automatic updates

From Mica 0.2.8 onward, signed releases check for updates on launch and hourly,
download them in the background, and install them when Mica quits. The browser's
normal CEF shutdown saves the session and closes its pages before replacement.
Use **Mica → Check for Updates…** for an immediate check, or **Automatically Keep
Mica Up to Date** to change the automatic-update preference. Sparkle persists the
preference; Mica does not reset it on launch. System profiling is disabled.

The [public release repository](https://github.com/martinrisseeuw/mica-releases)
contains only installers, checksums, and the signed update feed. Both feed and
archive signatures are verified before extraction. An installation older than
0.2.8 needs one upgrade to enable the updater; later versions update themselves.

## Included

- Real Chromium pages and Chrome DevTools docked at the bottom by default, with saved bottom, right, left, or separate-window placement. DevTools' own Dock side controls and Mica's menu stay synchronized. Includes Inspect Element.
- Address/search field with localhost, ports, IPv4/IPv6 loopback, HTTPS URLs, and DuckDuckGo search. The complete URL stays visible, including paths, query parameters, and fragments. Click or press Command-L to select the full address; click again to edit part of it. Local history suggests URLs and titles per space, selects an inline completion, and switches to an existing tab when possible.
- Minimal light sidebar from the [Paper design](https://app.paper.design/file/01M893AJRGZKRCEM7YG87V6Q5R/p-1-0): named pinned rows and collapsible folders above a divider, regular tabs below, favicon icons, active/hover close buttons, duplicate/reopen/close, and manual tab unloading.
- Default-on ad and tracker blocking, with per-site pause in the Privacy menu.
- A native, minimal start page from Paper: Mica mark, large focused search field, up to six pins from the current space, and keyboard hints. Pin shortcuts select the existing saved tab without creating a duplicate. New Tab reuses the current space's empty tab, including after session restoration.
- Named spaces with separate cookies, website storage, history, favicon caches, and extension profiles.
- Saved tabs, pins, active space, window size, and sidebar visibility. Restored inactive tabs load only when selected.
- Back/forward, reload, reload without cache, zoom, find in page, native download save dialogs, and recoverable network error pages.
- Light and dark appearances that follow macOS, a subtly translucent sidebar, and accessible AppKit controls. Sidebar toggling slides over 180 ms with ease-out timing, supports reversal during motion, and respects macOS Reduce Motion.
- `mica://extensions/` shows installed extensions in the current space, including enable/disable, details, permissions, removal, and keyboard shortcuts. The Extensions menu links to the official 1Password listing and Chrome Web Store.

Right-click a tab for its actions. **⌘W or the pin's × closes its live page**, keeps the saved pin, and resets its URL to the saved destination. Closed pins stay closed until selected; they are skipped when selecting another tab after a close. **Remove pinned tab** deletes the saved row. **Save Current URL to Pin** changes its saved destination. Ordinary tabs are removed on close.

Use **File → New Folder** or **right-click a tab → Move to Folder → New Folder**. Moving an ordinary tab into a folder pins it. Click a folder to expand/collapse; its context menu renames it or removes the folder while keeping its pins. Folders currently have one level. Click **⋯ beside the space name** for Rename Space, New Folder, New Space, and Delete Space. The space dropdown still switches spaces; the File menu and shortcuts remain available. **space name → ⋯ → Delete Space…** (also in **File → Delete Space…**) closes its tabs and removes it from the space picker after confirmation; at least one space must remain. Website data and installed extensions remain on disk, and `removed-spaces.json` retains a recovery copy of the removed space’s tabs and folders. This is not a website-data eraser.

Choose **Mica → Make Mica Default Browser…** to request HTTP and HTTPS link handling through macOS. The system asks for consent; this never runs automatically. Links from other apps open in the active space. Only web URLs are accepted from external applications.

Mica follows **System Settings → Appearance**, including live changes between Light, Dark, and Auto. The sidebar, top bar, and viewport margins share one native background blur and tint; macOS Reduce Transparency provides the solid alternative. Start pages, suggestions, extension controls, and browser chrome use matching adaptive colors. Website appearance follows the site's own support for the system color scheme. With the sidebar hidden, the viewport has equal 8 pt left and right margins; this inset blends into the sidebar animation.

Choose **DevTools ⋮ → Dock side** or **Developer → DevTools Position → Bottom / Right / Left / Window**. The frontend fills its panel without an extra Mica header. Both controls update the same saved placement, including docking back from a separate window. Docked DevTools stays attached to its tab and closes when that tab is unloaded or closed. The page and tools share one softly shadowed outer outline, with square corners at their seam.

Every placement uses Chromium’s bundled DevTools frontend and CEF’s native protocol transport. It opens no remote-debugging port. Each frontend has a separate debugging session; closing it detaches that session and resumes paused execution. Changing between a dock and a separate window recreates that frontend and its session; it can resume a paused page. Standard console evaluation, DOM/CSS inspection, debugging, and network tools use the inspected page’s protocol connection. Chrome host integrations such as local workspace folders and DevTools extensions are not implemented in this host, including Window mode.

| Shortcut | Action |
| --- | --- |
| ⌘L | Address/search |
| ⌘T | New tab |
| ⌘W | Close tab; unload a pin |
| ⇧⌘T | Reopen closed tab |
| ⌥⌘I / ⌥⌘J | Open Chrome DevTools |
| ⇧⌘P | Pin/unpin |
| ⇧⌘N | New space |
| ⌘S | Toggle sidebar |
| ⌘R / ⇧⌘R | Reload / reload without cache |
| ⌘[ / ⌘] | Back / forward |
| ⌘F | Find in page |
| Control+Tab / Control+Shift+Tab | Next / previous tab |
| ⌘1–8 / ⌘9 | Select tab / last tab |
| ⌘+ / ⌘− / ⌘0 | Zoom / reset |

## Address history and favicons

Suggestions match URL and page title within the current space. URL prefixes rank first, then frequency and recency. Up/Down selects, Enter opens or switches tabs, and Escape dismisses. Typing replaces a selected inline suffix; Right accepts it. Queries stay local. **Privacy → Clear History in This Space** clears saved visits; currently open tabs can still appear as suggestions.

History keeps up to 2,000 unique HTTP(S) URLs per space. Failed loads and internal pages are excluded, and URL credentials are stripped. Chromium supplies page-declared favicons without third-party icon services; icons are cached per origin and space. Favicons stay visible while tabs load; a globe covers missing icons. Background tabs may continue normal page activity. The active page shows loading through the Stop control and status text, without animated sidebar spinners.

## Extensions and 1Password

Click the puzzle icon or use **Extensions → Manage Extensions**. **Get 1Password** opens the official Chrome Web Store. Chromium handles installation prompts, permissions, updates, and real extension popups. Mica’s puzzle menu shows enabled extension actions in a four-column icon grid, including extensions without a keyboard shortcut. Click an icon to open it, its small pin to add/remove it beside the address bar, **Manage** for installed extensions, or **Add** for the store. Pins belong to the current space and persist across restarts. At narrow widths excess pinned icons remain accessible in the grid. Right-click a toolbar icon to unpin it; Escape or clicking outside dismisses the grid. Selecting an extension invokes Chromium's real action in the active tab, preserving its popup and `activeTab` permission. Opening an action from New Tab first opens the extension manager as its browser surface. No vendor extension code is redistributed with Mica.

You can also type **`mica://extensions/`** directly. This is a public alias for Chromium's built-in manager, embedded below Mica's own toolbar. Its installed list belongs to the active space; `mica://extensions/shortcuts` opens shortcut settings. Extension packages (`.crx` or `application/x-chrome-extension`) go to Chromium's installation/download handler instead of Mica's generic Save As panel. Normal downloads retain the native save dialog; extension source, signature, and permission checks remain Chromium's responsibility.

The Chromium toolbar exists internally for extension actions but stays hidden; Mica always displays its own address bar and sidebar. Extension-created native windows are hidden and their destination is reopened in a page-only Mica tab within the same space. That creates a new Chromium tab ID, so extensions that depend on the original tab ID or opener of those windows are not fully compatible. Normal webpage popups use CEF Views directly and preserve their opener. Programmatic `chrome.action.openPopup()` is limited by CEF's popup-style host; Mica's icon menu and registered action shortcuts use Chromium's real popup path.

To connect the 1Password desktop app, install the Developer ID signed Mica app in Applications, install the official extension, and add Mica under **1Password → Settings → Browser** as described in [1Password's trusted-browser instructions](https://support.1password.com/additional-browsers/). Sign in locally; no account secrets are part of the browser build or its tests.

On startup Mica discovers the installed 1Password app, verifies its browser helper's Apple signature and 1Password team identity, and registers that helper in Mica's own profile. Only the official stable extension is allowed to use this connector. Restart Mica if you install the desktop app afterward. Automated browser tests skip this connector and never connect to your desktop vault.

The isolated compatibility probe checks the official extension's enabled state, its rendered card in the installed overview, the manager's enable/disable controls using a separate minimal test extension, real content-script execution on localhost, its signed-out welcome page, an unpinned extension action without a shortcut, popup access to the active tab, pin/unpin controls, toolbar action access, pin persistence after restart, and the absence of Chrome's toolbar/tab strip in every page. These checks do not validate authenticated vault autofill, passkeys, or desktop pairing. The signed-out 1Password extension deliberately disables its vault popup until setup.

### Import extensions and settings from Chrome

Quit Chrome, then choose **Extensions → Import from Chrome…** (also **Import…**
in the puzzle menu). Choose a Chrome profile and up to 20 extensions. **Choose
folder…** supports a Chrome data folder in another location. Extensions already
installed in the destination space are skipped; unpacked and non-store
extensions must be installed manually.

**Include supported settings** is selected by default. Each row shows how many
preferences were recognized; hover over its checkbox to inspect the values.
The first version supports appearance and behavior preferences with recognized
names and types: themes, color schemes, selected display toggles, font size,
zoom, and bounded theme adjustments, including those inside standard settings
containers. It reads `chrome.storage.local` and the local copy of
`chrome.storage.sync`. Unknown preferences, arbitrary text, arrays, website
storage, IndexedDB, session storage, and managed policies are excluded. An
extension with no supported settings can still be installed.

**Continue to install** opens the selected Chrome Web Store listings. Complete
each normal installation prompt and finish extension setup. Then choose
**Extensions → Import Progress… → Apply settings**. Mica applies supported
preferences in the chosen space and closes its temporary import tab. Applying
is explicit because an extension’s setup can overwrite preferences.
Existing defaults outside the imported keys are retained. This is a one-time
import, not Chrome Sync. Accounts, authentication tokens, cookies, passwords,
Keychain items, and desktop-app pairing are not migrated; sign in again where
needed. Chromium’s existing extension compatibility limits still apply.

**Extensions → Import Progress…** shows waiting, ready, completed, and failed entries.
Pending imports survive restart; interrupted settings writes require an
explicit retry. Filtered preferences remain available for **Reapply settings**
if an extension resets them later. **Discard imports** removes saved preferences
and cancels unfinished imports, while keeping extensions already installed. If Chrome is running or a settings database
cannot be read, the affected row reports this; cancel and retry after quitting
Chrome to include those settings.

Chrome’s files are read without modification. LevelDB opens a bounded snapshot
in memory; only allowlisted preference values are saved in Mica’s import queue.
No raw Chrome database or account storage is copied into Mica. The allowlist is
in `src/ExtensionImport.mm`; extending support requires reviewing the preference
names, value types, and account-data boundary.

## Ad blocking

Rules are imported from [Search’s MIT-licensed Shield](https://github.com/driceroland/Search/blob/86bbffc26bf0496b6fee72a88a2fda69fd97bd50/Sources/Search/Shield.swift): 51 ad/tracker domains, generic and site-specific cosmetic selectors, and YouTube ad-request paths. CEF cancels matching third-party requests and injects cosmetic CSS into documents. First-party requests and Search’s YouTube script exception are preserved. Rules ship in the app; there is no startup list download.

Use **Privacy → Block Ads on This Site** to pause blocking for the current hostname, or **Privacy → Block Ads and Trackers** for the global setting. Both persist. Cosmetic rules are applied when a document finishes loading, so an ad slot may briefly appear. Search’s additional YouTube player-modification scripts are **not** included, and this does not promise to remove every video ad. The rules are a curated list, not a full uBlock Origin/EasyList engine.

To refresh the imported data from a reviewed Search checkout:

```sh
python3 scripts/import_search_shield.py /path/to/Search
./scripts/build.sh
```

Source revision and license are included in `resources/shield-rules.json` and `resources/LICENSE-Search.txt`.

## Build

Requires Xcode with its command line tools, Python 3.11+, and an Apple Silicon Mac. The bootstrap downloads pinned CEF and Sparkle distributions and installs CMake into `.tools/python`. It verifies the archives against upstream checksums. No global Python packages are installed.

```sh
git clone https://github.com/martinrisseeuw/mica.git
cd mica
python3 scripts/bootstrap.py
./scripts/build.sh
```

The release build, model tests, and local app signing run together. Output: `dist/Mica.app`.
On a fresh checkout, packaging uses an ad-hoc signature and needs no Apple
Developer account. Developer ID signing is used only when you configure an
identity. Download an official release above for normal installation and sharing.

Current engine: CEF `158.0.6+g23f1736`, Chromium `158.0.8127.89`. CEF is bundled, so the app is substantially larger than Search's system-WebKit implementation. Native controls and lazy restoration reduce avoidable work; no speed or memory advantage over Chrome/Electron has been benchmarked.

## Verification

```sh
.tools/python/bin/ctest --test-dir build --output-on-failure
python3 test/smoke.py
python3 test/extension_import.py
```

The integration test launches the real app with a disposable profile and a local HTTP fixture. It checks immediate typing, complete URL display/copying and first-click selection, a single empty tab per space, history completion and keyboard navigation, favicon restoration, minimum-size layout, ad blocking, DevTools console/DOM commands and full-panel layout, all four dock positions through the native and built-in controls, closing the DevTools window without closing its page, and resuming paused execution on detach. It also checks pinned rows and folders, Command-W without reopening closed pins, saved pin URLs, extension-download handoff, space cookie isolation, network error recovery, Command-Q, application Quit, window-close shutdown, and persistence after restart. Quit targets Mica’s controller directly because Chromium can replace the application delegate. Command-Q is handled at the application boundary so it never enters Chromium’s separate quit flow. Results are in `artifacts/`. Chromium's mock Keychain uses synthetic cookies, so the test does not access your normal browser profile or macOS Keychain. That mock is enabled only by the explicit test flag combined with a disposable `searchlight-smoke-*` profile and a localhost fixture URL.

The optional 1Password compatibility probe is separate from the browser regression suite:

```sh
curl -fL 'https://clients2.google.com/service/update2/crx?response=redirect&prodversion=158.0.8127.89&acceptformat=crx3&x=id%3Daeblfdkhhhdcdjpifhhbdiojplfjncoa%26uc' -o .tools/1password-probe.crx
python3 test/extensions.py
```

It records each checked behavior in `artifacts/extension-result.json` and fails when a check does not pass. The downloaded extension is not committed, packaged, or installed in the user's profile.

## Data and boundaries

New installations store data in `~/Library/Application Support/Mica/`. If an earlier Searchlight profile exists, the first launch offers **Start Fresh** (the default) or **Keep My Data**, before initializing Chromium. Starting fresh leaves Searchlight's data and Keychain item untouched. Keeping existing data reuses that profile and its original Keychain identity; macOS may require permission for the new signed app to use the old encryption key. The choice is saved in `Mica/profile-choice.json`. Do not run both browsers against a shared profile at once. `MICA_PROFILE` selects an absolute alternate path; `SEARCHLIGHT_PROFILE` remains supported for existing development setups.

`session.json` holds tabs/spaces; `Space-<uuid>/` contains each Chromium profile. `History/<uuid>.json` and `Favicons/<uuid>/` hold local suggestions and cached icons. `extension-imports.json` holds explicitly selected extension IDs, destination spaces, and filtered preference values while an import is pending. No accounts or other browser data are imported. HTTP/HTTPS and `about:blank` are allowed for ordinary navigation. Explicit extension routes are validated separately. `mica://extensions/` opens the embedded extension manager; the old `searchlight://extensions` route remains compatible. Webpages have no native JavaScript bridge. The bundled DevTools frontend alone receives a scoped protocol bridge.

Chromium's subprocess sandbox and TLS validation remain enabled. New profiles use **Mica Safe Storage**; existing profiles retain **Searchlight Safe Storage** so encrypted data stays readable. Ad-hoc rebuilds change code identity and can trigger repeated Keychain authorization. Developer ID signed builds with a stable bundle identifier and team preserve signing identity across updates. The first transition to Mica may still ask for access once. Tests use a disposable profile and mock Keychain, never the user's normal profile.

This is a developer preview. Sync, built-in password management, private spaces, and a complete downloads library are not implemented. Update the pinned CEF release, rebuild, and publish a signed release for engine security fixes.

## Signing and sharing

A Developer ID Application identity and an Apple notarization account are required for a normal outside-App-Store release. Neither a colleague's developer account nor a Developer ID Installer certificate is needed for the DMG workflow.

```sh
security find-identity -v -p codesigning
python3 scripts/package.py --identity 'Developer ID Application: YOUR TEAM (TEAM_ID)' --remember
xcrun notarytool store-credentials MicaNotary --team-id TEAM_ID
python3 scripts/release.py --identity 'Developer ID Application: YOUR TEAM (TEAM_ID)' --notary-profile MicaNotary
```

Enter the Apple ID and an app-specific password into notarytool's interactive prompt. Credentials stay in Keychain. Release packaging signs each framework library and helper before the app, enables the hardened runtime, timestamps signatures, notarizes and staples the app, creates and notarizes the DMG, then verifies Gatekeeper acceptance. The final DMG and SHA-256 file are written to `dist/`; notarization responses go to `artifacts/release/`. A rejected submission does not produce a final release file.

`--remember` stores only the public certificate fingerprint in the ignored `.tools/signing-identity` file, so later local builds retain the same signing identity. `--adhoc` explicitly opts into a development signature instead.

`python3 scripts/release.py --preview` tests disk-image packaging without credentials. Its output is explicitly named `-unnotarized.dmg` and is not the distributable release. The current package supports Apple Silicon on macOS 13+.

The update-signing key lives in the macOS Keychain under the account named in
`resources/updates.json`; that file contains only public configuration. Generate
or look up the key using `vendor/sparkle/bin/generate_keys --account nl.martnr.mica.updates`.
Keep the same key for future versions. Release packaging signs the completed DMG
and appcast with that key, verifies both, and writes the feed plus checksums to
`dist/updates/<version>/`. The publisher uploads only the explicit asset list,
checks GitHub's SHA-256 digests, and refuses to overwrite a published version.

```sh
python3 scripts/release.py --identity "$(cat .tools/signing-identity)" --notary-profile MicaNotary --notes-file resources/release-notes/0.2.9.txt
python3 scripts/publish.py --notes-file resources/release-notes/0.2.9.txt --publish
python3 test/updates.py
```

The update test replaces only a uniquely identified disposable copy of Mica via
a localhost signed feed, checks orderly shutdown, launches the updated copy, and
verifies saved space/pin/layout settings. Regular smoke tests never start the
production updater. Run native test suites sequentially because their windows
can affect each other's focus.

Entitlements follow the pinned Chromium 158 sources: JIT for renderer/GPU helpers; camera, microphone and printing for the main app. There are no debugging or library-validation exceptions. [CEF signing guidance](https://github.com/chromiumembedded/cef/blob/master/docs/code_signing.md).

Forks that distribute their own builds should use their own bundle identifier,
Developer ID identity, and update-signing key. Configure their release repository,
feed URL, public key, and Keychain account in `resources/updates.json` before
publishing. The checked-in key is public verification material for official Mica
releases; private signing keys and notarization credentials stay in Keychain.

## Contributing

Bug reports and pull requests are welcome. Include your macOS and Mica versions
and reproduction steps when reporting a bug. Keep changes focused and run the
checks relevant to the change; run native test suites sequentially as described
above. Use `feature/`, `fix/`, or `chore/` branch names and Conventional Commit
messages.

Build output, downloaded dependencies, browser profiles, and signing credentials
belong outside version control. Contributions to Mica's own code are provided
under the project's MIT license; preserve notices on third-party material.

## License

Mica's original source code is licensed under the [MIT license](LICENSE),
copyright 2026 Martin Risseeuw. Builds include it as
`Mica.app/Contents/Resources/LICENSE-Mica.txt`. Third-party components retain their own licenses;
see [Third-party notices](THIRD_PARTY_NOTICES.md), [CEF's license](LICENSE-CEF.txt),
and [Search's license](resources/LICENSE-Search.txt).

## Source

- `src/Browser.mm`: native AppKit UI and CEF tab lifecycle.
- `src/StartPage.mm`: native, responsive new-tab surface matching Paper artboard 06.
- `src/SidebarUI.inc`: pinned rows, folder actions, and regular tabs.
- `src/DockClient.h`, `src/ToolsConnection.h`, `src/RendererApp.h`, `resources/devtools-host.js`: scoped docked DevTools transport.
- `src/Shield.mm`, `src/ShieldRequest.h`: network and cosmetic ad blocking.
- `src/Model.mm`: address resolution and validated session persistence.
- `src/History.mm`, `src/HistoryUI.inc`: per-space history, native suggestions, and favicon cache.
- `src/ExtensionPanel.mm`, `src/ExtensionsUI.inc`, `src/ChromeExtensions.h`: native extension grid, toolbar pins, and Chrome integration.
- `src/main.mm`: sandboxed CEF startup, native application, and shutdown.
- `src/helper.cc`: CEF's sandboxed subprocess entry point.
- `scripts/`: bootstrap, build, packaging, and reproducible icon source.
- `test/`: model and native integration tests.

The CEF-derived helper entry point and bundled framework use the terms in `LICENSE-CEF.txt`; Chromium dependency notices are included in the application bundle. This project is independent of Search and Office Commun.
