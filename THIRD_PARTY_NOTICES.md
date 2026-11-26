# Third-party notices

Mica's original code is licensed under the root `LICENSE` (MIT). That license
does not replace the notices and license terms of the components below.

Chromium Embedded Framework (CEF), Copyright The Chromium Embedded Framework Authors, is distributed under the BSD-style license in LICENSE-CEF.txt. `src/helper.cc` is derived from CEF's `tests/cefsimple/process_helper_mac.cc`.

The bundled Chromium Embedded Framework includes Chromium and other third-party components. Their notices are copied from the official distribution into `Mica.app/Contents/Resources/CREDITS.html`.

CEF project: https://github.com/chromiumembedded/cef
CEF distribution: https://cef-builds.spotifycdn.com/

The ad-block rule data in `resources/shield-rules.json` is adapted from Search, Copyright (c) 2026 Office Commun, under the MIT license in `resources/LICENSE-Search.txt`. The imported source revision is `86bbffc26bf0496b6fee72a88a2fda69fd97bd50`: https://github.com/driceroland/Search. The import contains data from `Sources/Search/Shield.swift` and `Sources/Search/YouTubeAds.swift`; it does not include Search's YouTube player scripts.

The docked developer tools use the unmodified Chromium DevTools frontend bundled with CEF, under the Chromium notices above. The Searchlight transport adapter is separate from that frontend.

Sparkle 2.10.1 provides native macOS updates, under the license bundled as
`Mica.app/Contents/Resources/LICENSE-Sparkle.txt`.
Project and source: https://github.com/sparkle-project/Sparkle/tree/2.10.1

LevelDB 1.23 and Snappy 1.2.2 read Chrome extension settings from an in-memory
snapshot. Both use BSD-style licenses, bundled as `LICENSE-LevelDB.txt` and
`LICENSE-Snappy.txt` in the app’s Resources directory. Source archives and
SHA-256 checksums are pinned in `scripts/bootstrap_import.py`.
Sources: https://github.com/google/leveldb/tree/1.23 and
https://github.com/google/snappy/tree/1.2.2
