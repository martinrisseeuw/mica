# Mica interface references

Editable source: [Paper, artboards 06–10](https://app.paper.design/file/01M893AJRGZKRCEM7YG87V6Q5R/p-1-0).

These JSX exports are design references, not application runtime code. AppKit
implements them in `src/StartPage.mm`, `src/SidebarUI.inc`, and `src/ExtensionPanel.mm`. macOS system fonts
and symbols provide native input, focus, accessibility, and keyboard behavior.

Paper tokens: surface `#FFFFFF`, chrome `#F5F5F5`, border `#E4E4E4`, text `#232323`,
muted `#686868`, accent `#3D4A55`, selected `#E6E7E8`. Start-page text uses SF Pro
at 28/16/13/12 pt, with a 560 × 64 pt search surface. Sidebar rows are 192 × 36 pt,
with 16 pt indentation inside folders. Native layouts adapt to smaller windows.

The native start page now shows up to six pins from the current space in place
of the original localhost/MDN sample shortcuts. The input and placeholder share
the same font and are vertically centered using the native field height.

Artboard 07 defines the extension grid: 312 pt panel, 16 pt padding, 64 × 56 pt
icon tiles in four columns with 8 pt gaps, 24 pt icons, 20 pt pin controls, and
11 pt labels. `extension-grid.jsx` is its exact Paper export. The native grid
scrolls after four rows; toolbar overflow remains accessible in the grid. Pins
are stored per space in Chromium’s preference store.

Artboard 08 defines one shared outer viewport for the page and docked DevTools,
with an 8 pt radius and subtle shadow. Inner seams are square in bottom/left/right
placements. `viewport-dock.jsx` preserves the Paper geometry and tokens.

Sidebar motion: 180 ms ease-out (cubic), moving sidebar, toolbar and page together.
A toggle during motion reverses from the current position. macOS Reduce Motion
uses the final layout immediately. Tab favicons stay steady during loading.

Artboard 09 places an ellipsis button beside the space picker. Its menu contains
Rename Space, New Folder, New Space, and Delete Space, with deletion separated
at the bottom. `space-menu.jsx` preserves the Paper reference; `src/Browser.mm`
uses a native NSMenu for system spacing, typography, keyboard navigation, and
accessibility. Deletion requires confirmation, Cancel is the default, and the
last remaining space cannot be deleted. The menu stays bound to its original
space if the active selection changes while it is open.

Artboards 09–10 show light and dark appearances. `system-light.jsx` and
`system-dark.jsx` preserve the exact exports. The sidebar tint in Paper illustrates wallpaper showing through;
the app uses one AppKit material behind the whole browser frame, following
window activation and macOS Reduce Transparency. It does not paint a fixed glow.
`src/Appearance.mm` defines paired surface, chrome, text, and control colors.
Windows inherit the system appearance, including changes while Mica is open.

Native behavior references: [Apple sidebar material](https://developer.apple.com/documentation/appkit/nsvisualeffectview)
and [default application consent](https://developer.apple.com/documentation/appkit/nsworkspace/setdefaultapplication(at:toopenurlswithscheme:completion:)).

The top bar, sidebar, and margins are transparent overlays on that shared material.
With the sidebar hidden, viewport gutters are 8 pt on both sides. The left inset
interpolates from 0 to 8 pt as the sidebar closes, preserving smooth motion.

The 56 pt top bar shares a 28 pt vertical centerline across the native traffic
lights, sidebar toggle, navigation, and extension icons. The traffic-light group
starts at 18 pt and retains AppKit's button sizes, spacing, actions, and hover
behavior. The collapsed sidebar toggle starts at 90 pt, leaving room after the
window buttons. `src/WindowChrome.mm` keeps the native titlebar hit area aligned
after AppKit updates and restores native geometry for fullscreen transitions.
