# Todo + Calendar (Omarchy plugin)

Persistent todo list and calendar, docked or floating on a chosen
monitor. See `docs/superpowers/specs/2026-09-09-omarchy-todo-calendar-plugin-design.md`
for the full design.

## Install

    ln -s "$(pwd)/plugin" ~/.config/omarchy/plugins/sebastiangrant.dashboard
    cp plugin/config.example.json plugin/config.json

Edit `plugin/config.json`:

- `monitor`: exact output name from `hyprctl monitors -j` (the `name` field).
- `mode`: `"docked"` (reserves screen space) or `"floating"` (overlay).
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

## Toggling docked/floating live

    omarchy-shell sebastiangrant.dashboard toggleMode

Bind this to a key in `~/.config/hypr/bindings.lua` for one-key toggling.
This repo binds it to `SUPER + T`.

## Data layout

    <dataDir>/today.json       # due today or overdue
    <dataDir>/thisweek.json    # due later this ISO week
    <dataDir>/thismonth.json   # due later this month
    <dataDir>/someday.json     # no due date, or due beyond this month
    <dataDir>/archive/YYYY-MM.json   # completed tasks, by completion month

## Known v1 limitations

- No git/cloud sync built in — point `dataDir` at an already-synced folder.
- No calendar event creation — `.ics` files are read-only.
- No recurring-event expansion — only non-recurring events show.
- No file locking — last write wins if you edit files externally while
  the shell is also writing.
- `config.json` does not hot-reload on the real deployed shell:
  `omarchy-launch-shell` sets `QS_DISABLE_FILE_WATCHER=1`, which disables
  the file watcher that would otherwise pick up changes automatically.
  After editing `plugin/config.json`, run `omarchy restart shell` for the
  change to take effect.
