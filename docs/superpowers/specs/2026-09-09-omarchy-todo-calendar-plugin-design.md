# Omarchy Todo + Calendar Plugin — Design

Date: 2026-09-09
Status: Approved

## Purpose

A persistent Omarchy shell widget showing a todo list and a calendar,
pinned to a specific monitor's right edge. It should be able to dock
(reserving screen space) or float (overlay, no space reservation), and
switch between the two live via a keybind. Todo data should be plain
files a user can drop into Git, iCloud Drive, Google Drive, etc. and
sync themselves — no sync logic lives in the plugin for v1.

## Context: how Omarchy shell plugins work

Omarchy's bar, notifications, and all overlays run inside one
long-running Quickshell (QML) process, `omarchy-shell`. Plugins are
discovered from `~/.config/omarchy/plugins/<plugin-id>/manifest.json`
(user-owned) or bundled first-party ones under
`$OMARCHY_PATH/shell/plugins/`. Manifests declare one or more `kinds`:
`bar`, `bar-widget`, `overlay`, `panel`, `menu`, `service`.

This project uses `kind: "service"`. Services are mounted once at
shell startup (not summoned/dismissed like overlays) and get a few
properties injected by the host (`shell`, `manifest`,
`pluginRegistry`) but — unlike bar-widget layout entries — get **no
per-instance settings object** from `shell.json`; that's bar-specific
plumbing (`entrySettings()` in `BarModel.js`), not a general plugin
API. `shellConfigProvider`/`shellConfigMutator` on the plugin registry
are explicitly internal ("wired by shell.qml"), so this plugin does
not depend on them.

A first-party plugin like `omarchy.background` shows the pattern for
a per-monitor persistent surface: a `Variants { model: Quickshell.screens }`
wrapping a `PanelWindow` with `WlrLayershell` anchors, one instance per
matching screen. This plugin follows the same shape, filtered to a
single configured monitor name instead of all screens.

Reference plugins read during design: `background` (per-screen
`PanelWindow` + `WlrLayershell`), `reminders` (`overlay` kind,
`keepLoaded: true`), `nightlight`/`idle` (minimal `service` manifests),
`PluginRegistry.qml` (manifest validation, `isEnabled()` rules),
`shell.qml` `ensureService()` (what gets injected into a service
instance).

## Non-goals (v1)

- No built-in git/cloud sync (config option left open for later; user
  points `dataDir` at an already-synced folder themselves).
- No calendar event creation/editing — `.ics` files are read-only.
- No RRULE/recurrence expansion — only non-recurring `VEVENT`s are
  shown. This is a deliberate scope cut, not an oversight: recurrence
  expansion is a meaningfully larger parsing problem.
- No multi-monitor broadcast — the plugin targets exactly one
  configured monitor by name.
- No file locking / merge conflict resolution across sync tools —
  last write wins, files are watched and reloaded on external change.

## Architecture

```
~/.config/omarchy/plugins/sebastiangrant.dashboard/
├── manifest.json            # schemaVersion 1, kinds: ["service"]
├── config.json              # user-owned settings (see below)
├── Main.qml                 # service entry point: per-monitor PanelWindow
├── TodoStore.qml            # todo file I/O + rollover logic
├── TodoPane.qml             # todo list UI
├── CalendarPane.qml         # month grid UI
├── IcsParser.js             # minimal VEVENT/DTSTART/SUMMARY parser
└── Util.js                  # date bucketing helpers (ISO week math, etc.)
```

`manifest.json`:

```json
{
  "schemaVersion": 1,
  "id": "sebastiangrant.dashboard",
  "name": "Todo + Calendar",
  "version": "1.0.0",
  "author": "sebastiangrant",
  "description": "Persistent todo list and calendar docked/floating on a monitor",
  "kinds": ["service"],
  "entryPoints": { "service": "Main.qml" }
}
```

Enabling it requires one line in `~/.config/omarchy/shell.json`'s
top-level `plugins[]` array (non-first-party services must be listed
there to load, per `PluginRegistry.isEnabled()`):

```json
"plugins": [{ "id": "sebastiangrant.dashboard" }]
```

### Settings: `config.json`

Sibling to `manifest.json`, read via `FileView { watchChanges: true }`
so edits apply live without a shell restart:

```json
{
  "monitor": "HDMI-A-1",
  "mode": "floating",
  "width": 340,
  "dataDir": "~/Sync/omarchy-todo",
  "icsFiles": ["~/Sync/calendar/personal.ics"]
}
```

- `monitor`: exact Hyprland output name (`hyprctl monitors -j` → `name`).
- `mode`: `"docked"` or `"floating"`; can also be flipped live via IPC
  (below) without touching this file.
- `dataDir`: expanded `~`; created on first run if missing.

### Docked vs. floating

- **Docked**: `WlrLayershell.layer: WlrLayer.Top`,
  `exclusionMode: ExclusionMode.Exclusive`, anchored `right`/`top`/`bottom`.
  Hyprland treats the reserved strip like the bar's reserved area —
  tiled windows shrink to avoid it.
- **Floating**: same anchors, `exclusionMode: ExclusionMode.Ignore`.
  Windows can go edge-to-edge underneath it.

### Live mode toggle (IPC)

```qml
IpcHandler {
  target: "sebastiangrant.dashboard"
  function toggleMode(): void { root.setMode(root.mode === "docked" ? "floating" : "docked") }
}
```

Bind a Hyprland key to it during implementation (via the `omarchy`
skill, editing `~/.config/hypr/bindings.lua`):

```
exec, omarchy-shell sebastiangrant.dashboard toggleMode
```

### Monitor targeting and fallback

`Variants { model: Quickshell.screens }` filters to
`modelData.name === config.monitor`. If no screen matches (monitor
unplugged/renamed), fall back to `Quickshell.screens[0]` and
`console.warn` — the widget should never simply fail to appear.

## Todo data model

One task:

```json
{
  "id": "t_1936400000000",
  "text": "Buy milk",
  "dueDate": "2026-09-10",
  "notes": "",
  "createdAt": "2026-09-09T10:00:00Z",
  "completedAt": null
}
```

`id` is a timestamp-based string (`"t_" + Date.now()` + a short random
suffix to avoid same-millisecond collisions) — good enough for a
single-writer personal store, no UUID library needed.

### Bucket files

Under `dataDir`, an **open** task lives in exactly one of:

| File | Contents |
|---|---|
| `today.json` | due today or overdue |
| `thisweek.json` | due later this ISO week (Mon–Sun) |
| `thismonth.json` | due later this calendar month |
| `someday.json` | no due date, or due beyond this month |

A **rollover** pass recomputes every open task's correct bucket from
today's date and rewrites all four files. It runs:

1. On plugin startup.
2. On a daily timer armed for the next local midnight.
3. Immediately after any add/edit that changes a `dueDate`.

Rollover reads all four files, merges their tasks into one working
list, re-sorts each task into its bucket by `dueDate` vs. today, and
writes each file back **atomically** (write to `<file>.tmp`, then
rename) — so a sync tool watching the folder never observes a
half-written file.

### Completion → archive

Checking a task off removes it from its current bucket file
immediately (not deferred to rollover) and appends it, with
`completedAt` set, to `archive/YYYY-MM.json` (month = completion date,
created on first use). This is the growth valve: bucket files only
ever hold currently-open tasks; completed history accumulates in
dated archive files instead of bloating the working set.

### Week/month boundaries

- Week = ISO week, Monday start, Sunday end.
- Month = calendar month.
- All date comparisons use local date only (no time-of-day), so a
  task due "today" stays in `today.json` all day regardless of
  when it was created.

## Calendar

- Month grid computed purely from `Date` — no external data required
  for the grid itself (current month, today highlighted, prev/next
  navigation).
- `.ics` files listed in `config.icsFiles` are parsed by a small
  hand-rolled parser (`IcsParser.js`) extracting `VEVENT` blocks'
  `DTSTART` and `SUMMARY` (ignoring `RRULE`, per the non-goals above).
  Malformed files are skipped individually with a `console.warn`, not
  fatal to the whole plugin.
- Days with one or more parsed events show a dot indicator; selecting
  a day lists that day's event summaries below the grid.
- Refresh: re-parse on file change (`FileView { watchChanges: true }`
  per configured path) rather than polling.

## Error handling

| Failure | Behavior |
|---|---|
| Configured monitor not found | Fall back to first available screen; `console.warn` |
| `config.json` missing | Use built-in defaults (dock right edge of primary screen, `dataDir` under `~/.local/share/sebastiangrant.dashboard/`, no `.ics` files) |
| Bucket/archive JSON malformed | Treat as empty list for that file; `console.warn`; do not crash the shell |
| `dataDir` missing | Created on first run |
| `.ics` file malformed or unreadable | Skip that file only; other configured files still parse |

## Testing plan

This runs inside the live `omarchy-shell` process, so verification is
manual/exploratory rather than an automated suite:

- Standalone script (Node or plain JS run outside QML) exercising the
  bucketing/rollover math against fixed fake "today" dates, before
  wiring it into `TodoStore.qml` — catches off-by-one week/month
  boundary bugs cheaply.
- Add/complete/edit tasks through the UI; confirm correct bucket file
  updates and archive appends by inspecting the JSON files directly.
- Force a rollover across a simulated day boundary (temporarily fake
  "today" in `Util.js`) and confirm tasks migrate buckets correctly.
- Toggle `mode` via the IPC call; confirm docked reserves space
  (`hyprctl clients`/visual check that tiled windows shrink) and
  floating does not.
- Point `config.monitor` at a nonexistent output name; confirm
  fallback-to-first-screen behavior and the warning.
- Point `icsFiles` at a deliberately malformed `.ics`; confirm the
  plugin still loads and other panes still work.
