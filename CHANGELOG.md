# Changelog

## 0.3.0 — 2026-10-23

**Triggers per app.** Finder and Preview now each have their own pinch, keyboard shortcut, scroll and mouse-button settings.

- Pick Finder or Preview at the top of Settings and set up its triggers separately. Settings opens on whichever app you were in.
- Preview no longer opens the grid when you pinch to zoom out of a photo or PDF. Pinch is off for Preview by default, and it
  listens to the shortcut instead. Turn pinch back on with a key to hold (e.g. ⌥) and zooming stays untouched.
- A warning appears if Preview's pinch is on with no key to hold.
- Each app can record a different shortcut. Tabview swaps to the right one as you switch apps, and the menu bar shows the
  shortcut for the app in front.
- Your existing trigger settings carry over to both apps, except pinch in Preview.

## 0.2.0 — 2026-10-22

First public release.

- Pinch in over a Finder or Preview window to see every tab as a card; pinch out to leave
- Finder cards preview the files inside each folder; Preview cards show the document itself
- Search, arrow keys, Return to switch, ⌘W to close
- Choose your trigger: pinch (optionally with a held key), any keyboard shortcut, modifier + scroll, or a mouse button
- `tabview://show|hide|toggle|settings` for Raycast, Shortcuts and scripts
