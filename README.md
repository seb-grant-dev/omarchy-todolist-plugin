# Todo + Calendar (Omarchy plugin)

Persistent todo list and calendar, docked, floating, or hidden on a chosen
monitor. See `docs/superpowers/specs/2026-09-09-omarchy-todo-calendar-plugin-design.md`
for the full design.

## Install

    ln -s "$(pwd)/plugin" ~/.config/omarchy/plugins/sebastiangrant.dashboard
    cp plugin/config.example.json plugin/config.json

Edit `plugin/config.json`:

- `monitor`: exact output name from `hyprctl monitors -j` (the `name` field).
- `mode`: `"docked"` (reserves screen space), `"floating"` (overlay), or
  `"hidden"` (panel is not shown).
- `width`: panel width in pixels (the panel always spans the full height of
  the target monitor; only the width is configurable).
- `dataDir`: where todo JSON files live — point this at a Git/iCloud/Drive
  synced folder to share your list across machines yourself; the plugin
  does no syncing on its own.
- `icsFiles`: array of local `.ics` file paths to show as calendar events
  (non-recurring events only — no RRULE expansion).

Enable it in `~/.config/omarchy/shell.json`:

```json
"plugins": [{ "id": "sebastiangrant.dashboard" }]
```

Then `omarchy restart shell`.

## Cycling docked/floating/hidden live

    omarchy-shell sebastiangrant.dashboard toggleMode

Each call advances to the next mode in order: docked → floating → hidden →
docked → ...

Bind this to a key in `~/.config/hypr/bindings.lua` for one-key cycling.
This repo binds it to `SUPER + T`. **Note:** `SUPER + T` is Omarchy's stock
binding for "toggle window floating/tiling"; binding it here replaces that
default, so the deployed system unbinds the stock action first. The actual
snippet added to `~/.config/hypr/bindings.lua`:

```lua
-- Dashboard plugin
-- Unbind existing SUPER+T (was: toggle window floating/tiling)
hl.unbind("SUPER + T")
o.bind("SUPER + T","Cycle dashboard docked/floating/hidden","omarchy-shell sebastiangrant.dashboard toggleMode")
```

## Data layout

    <dataDir>/today.json       # due today or overdue
    <dataDir>/thisweek.json    # due later this ISO week
    <dataDir>/thismonth.json   # due later this month
    <dataDir>/someday.json     # no due date, or due beyond this month
    <dataDir>/archive/YYYY-MM.json   # completed tasks, by completion month

## Behavioral notes

- The panel uses `WlrKeyboardFocus.OnDemand`, so clicking a checkbox,
  calendar day, or text field can steal keyboard focus away from whatever
  window you were previously typing in. Focus returns to normal once you
  click back into another window.
- The panel uses `WlrLayer.Top`, so in floating mode it paints over
  fullscreen windows (video players, games, etc.) with no auto-hide —
  there's no way to make it temporarily get out of the way short of
  toggling to a different monitor or removing the plugin.

## Tests

Two standalone Node test harnesses (no Quickshell/QML runtime needed):

    node plugin/scripts/test-util.js          # due-date bucketing logic
    node plugin/scripts/test-ics-parser.js    # minimal .ics VEVENT parser

## Known v1 limitations

- No git/cloud sync built in — point `dataDir` at an already-synced folder.
- No calendar event creation — `.ics` files are read-only.
- No recurring-event expansion — only non-recurring events show.
- No file locking — last write wins if you edit files externally while
  the shell is also writing.
- No way to edit a task's due date once set — only delete and re-add it.
  `TodoStore.qml`'s `editDueDate` function exists and works, but v1 has no
  UI control that calls it.
- **Nothing hot-reloads on the real deployed shell, and this can silently
  discard external changes.** `omarchy-launch-shell` sets
  `QS_DISABLE_FILE_WATCHER=1`, which disables Quickshell's file watcher
  shell-wide — not just for `config.json`. This equally affects the four
  bucket JSON files and any configured `.ics` file: if you sync in a
  change from another machine (via your `dataDir` sync mechanism) while
  the shell is already running, the plugin won't notice until
  `omarchy restart shell`. More importantly, the plugin still holds its
  last-loaded copy of the bucket files in memory — so the *next* local
  edit you make (checking off a task, adding one, anything that triggers
  a write) will overwrite the on-disk file with that stale in-memory
  copy, **silently discarding whatever arrived externally**, with no
  warning. If you edit `dataDir` files or `.ics` files from elsewhere
  while the shell is running, run `omarchy restart shell` afterward
  before touching the plugin again. The same applies to `config.json`:
  after editing it, run `omarchy restart shell` for the change to take
  effect.
