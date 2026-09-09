# Omarchy Todo + Calendar Plugin Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build an Omarchy shell `service` plugin that shows a persistent todo list and calendar, docked or floating on a chosen monitor, matching the approved design spec.

**Architecture:** A single Quickshell (QML) `service`-kind plugin at `~/.config/omarchy/plugins/sebastiangrant.dashboard/` (symlinked to this repo's `plugin/` directory for development), mounting one `PanelWindow` on the configured monitor via `WlrLayershell`, with plain-JSON due-date-bucketed todo storage (`today.json`/`thisweek.json`/`thismonth.json`/`someday.json` + monthly `archive/YYYY-MM.json`) and a month-grid calendar that overlays events parsed from local `.ics` files.

**Tech Stack:** QML / Quickshell (`Quickshell`, `Quickshell.Io`, `Quickshell.Wayland`), the shell's own `qs.Commons` (`Color`, `Style`) singletons for theming, plain JS modules for pure logic (dual-loadable from QML and Node), Node.js only as a throwaway harness for testing the pure-JS logic (no framework — none exists in this environment).

**Spec:** `docs/superpowers/specs/2026-09-09-omarchy-todo-calendar-plugin-design.md`

## Global Constraints

- Plugin id is exactly `sebastiangrant.dashboard` (spec, confirmed with user).
- No sync/git/cloud logic in the plugin itself — `dataDir` is just a configurable folder path (spec Non-goals).
- No RRULE/recurrence expansion — events whose `VEVENT` block contains an `RRULE` line are excluded entirely from calendar output, not partially shown (spec Non-goals + Calendar section).
- No file locking / merge conflict handling — last write wins; files are watched and reloaded on external change (spec Todo data model).
- `ExclusionMode` has exactly three values: `Normal`, `Ignore`, `Auto` (confirmed against `/usr/lib/qt6/qml/Quickshell/_Window/quickshell-window.qmltypes` during planning — the spec originally said `Exclusive`, which does not exist, and has been corrected). Docked mode uses `Auto`; floating uses `Ignore`.
- `WlrLayer` values: `Background`, `Bottom`, `Top`, `Overlay`. `WlrKeyboardFocus` values: `None`, `Exclusive`, `OnDemand` (confirmed against `quickshell-wayland-layershell.qmltypes`).
- All plugin QML files may `import qs.Commons` (for `Color`/`Style`) because every plugin — first-party or user — loads into the one shared `omarchy-shell` `QQmlEngine`, which already registers that import path for `shell.qml` itself. Task 1 verifies this assumption before any other work depends on it.
- Every JSON file write goes through Quickshell `FileView` with `atomicWrites: true` (not manual temp-file/rename) — this is Quickshell's built-in mechanism for exactly the atomicity the spec calls for.
- Every date computation in a testable helper (`Util.js`, `IcsParser.js`) takes "today" (or the parse input) as an explicit parameter — no internal `new Date()` calls inside logic that a test needs to control.
- `qs.Commons`'s own `qmldir` registers a singleton literally named `Util` (`Commons/Util.qml`) alongside `Color`/`Style`/`Border`. Any file that both `import qs.Commons` and needs this plugin's own `Util.js` (date bucketing) must alias the local one to avoid a name collision — `CalendarPane.qml` does this (`import "Util.js" as DateUtil`); `TodoStore.qml` doesn't import `qs.Commons` so it keeps the plain `Util` alias.

---

## Task 1: Plugin skeleton, theming smoke test, and install

**Files:**
- Create: `plugin/manifest.json`
- Create: `plugin/config.example.json`
- Create: `plugin/Main.qml`
- Create: `.gitignore`

**Interfaces:**
- Produces: the installed, loadable plugin shell at `~/.config/omarchy/plugins/sebastiangrant.dashboard/` (symlink to `plugin/`), which every later task edits in place.
- Produces: `plugin/config.json` (gitignored, real per-machine settings) as a copy of `config.example.json` for later tasks to read.

- [ ] **Step 1: Write the manifest**

`plugin/manifest.json`:

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

- [ ] **Step 2: Write the example config**

`plugin/config.example.json`:

```json
{
  "monitor": "HDMI-A-1",
  "mode": "floating",
  "width": 340,
  "dataDir": "~/.local/share/sebastiangrant.dashboard",
  "icsFiles": []
}
```

- [ ] **Step 3: Write a minimal Main.qml that only proves the load path and theming import work**

`plugin/Main.qml`:

```qml
import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons

Item {
  id: root

  Variants {
    model: Quickshell.screens.length > 0 ? [Quickshell.screens[0]] : []

    PanelWindow {
      id: panel
      required property var modelData
      screen: modelData

      anchors { top: true; bottom: true; right: true }
      implicitWidth: 340
      color: Color.background

      WlrLayershell.namespace: "sebastiangrant-dashboard"
      WlrLayershell.layer: WlrLayer.Top
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
      exclusionMode: ExclusionMode.Ignore

      Text {
        anchors.centerIn: parent
        text: "sebastiangrant.dashboard loaded"
        color: Color.foreground
        font.pixelSize: Style.font.heading
      }
    }
  }

  Component.onCompleted: console.log("sebastiangrant.dashboard: Main.qml loaded")
}
```

- [ ] **Step 4: Add a `.gitignore` for the real (per-machine) config**

`.gitignore`:

```
plugin/config.json
```

- [ ] **Step 5: Install — symlink the plugin directory and enable it**

```bash
ln -s "$(pwd)/plugin" ~/.config/omarchy/plugins/sebastiangrant.dashboard
cp plugin/config.example.json plugin/config.json
```

Edit `~/.config/omarchy/shell.json`'s top-level `plugins` array to include:

```json
"plugins": [{ "id": "sebastiangrant.dashboard" }]
```

- [ ] **Step 6: Restart the shell and verify it loads**

```bash
omarchy restart shell
journalctl --user -u <omarchy-shell-unit> -n 50 --no-pager 2>/dev/null || true
```

If there's no systemd unit for the shell in this session, instead check
whatever terminal/log `omarchy-shell` prints to on restart for the line
`sebastiangrant.dashboard: Main.qml loaded` and for the absence of any
`PluginRegistry:` or `service plugin load failed` warnings mentioning
`sebastiangrant.dashboard`.

Expected: the log line appears, no warnings for this plugin id, and a
themed rectangle (using the active theme's background/foreground colors,
not hardcoded ones) appears docked to the right edge of your primary
monitor reading "sebastiangrant.dashboard loaded". This confirms both the
manifest/load path and the `qs.Commons` import assumption before any
later task depends on it.

If the plugin does not appear at all: run `omarchy-shell shell rescanPlugins`
(per Omarchy's plugin hot-reload docs) and restart again before treating
this as a real failure.

- [ ] **Step 7: Commit**

```bash
git add plugin/manifest.json plugin/config.example.json plugin/Main.qml .gitignore
git commit -m "$(cat <<'EOF'
Add plugin skeleton and verify it loads in omarchy-shell

Confirms the service-plugin load path and qs.Commons theming import
before building real functionality on top of them.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01QeLfQxs4RoVptycMn9vDnd
EOF
)"
```

---

## Task 2: Date-bucketing logic (`Util.js`)

**Files:**
- Create: `plugin/Util.js`
- Create: `plugin/scripts/test-util.js`

**Interfaces:**
- Produces: `Util.toISODate(date)`, `Util.parseISODate(str)`, `Util.startOfISOWeek(date)`, `Util.endOfISOWeek(date)`, `Util.endOfMonth(date)`, `Util.bucketFor(dueDateStr, today)` — all pure functions of their arguments, no internal `new Date()`. `bucketFor` returns one of `"today"`, `"thisweek"`, `"thismonth"`, `"someday"`.
- Consumed by: `TodoStore.qml` (Task 3), imported as `import "Util.js" as Util`.

- [ ] **Step 1: Write the test harness first (it will fail — the module doesn't exist yet)**

`plugin/scripts/test-util.js`:

```js
const assert = require("assert")
const Util = require("../Util.js")

function run() {
  // Anchor "today" at a fixed date, but derive week/month boundaries from
  // Util itself rather than hardcoding a weekday, so the test doesn't
  // depend on which day of the week 2026-09-09 happens to be.
  const today = new Date(2026, 8, 9) // 2026-09-09, local midnight

  assert.strictEqual(Util.toISODate(today), "2026-09-09")

  const monday = Util.startOfISOWeek(today)
  const sunday = Util.endOfISOWeek(today)
  const monthEnd = Util.endOfMonth(today)

  assert.ok(monday.getDay() === 1, "startOfISOWeek must land on a Monday")
  assert.ok(sunday.getDay() === 0, "endOfISOWeek must land on a Sunday")
  assert.ok(monday.getTime() <= today.getTime() && today.getTime() <= sunday.getTime(),
    "today must fall within its own ISO week")

  // No due date -> someday
  assert.strictEqual(Util.bucketFor(null, today), "someday")
  assert.strictEqual(Util.bucketFor("", today), "someday")

  // Today and overdue -> today
  assert.strictEqual(Util.bucketFor(Util.toISODate(today), today), "today")
  const yesterday = new Date(today.getFullYear(), today.getMonth(), today.getDate() - 1)
  assert.strictEqual(Util.bucketFor(Util.toISODate(yesterday), today), "today")

  // End of this ISO week (but after today, unless today IS Sunday) -> thisweek,
  // unless sunday === today in which case it's already covered by the
  // "today" case above.
  if (Util.toISODate(sunday) !== Util.toISODate(today)) {
    assert.strictEqual(Util.bucketFor(Util.toISODate(sunday), today), "thisweek")
  }

  // Day after this ISO week, still within this month -> thismonth
  const dayAfterWeek = new Date(sunday.getFullYear(), sunday.getMonth(), sunday.getDate() + 1)
  if (Util.toISODate(dayAfterWeek) <= Util.toISODate(monthEnd)) {
    assert.strictEqual(Util.bucketFor(Util.toISODate(dayAfterWeek), today), "thismonth")
  }

  // Day after month end -> someday
  const dayAfterMonth = new Date(monthEnd.getFullYear(), monthEnd.getMonth(), monthEnd.getDate() + 1)
  assert.strictEqual(Util.bucketFor(Util.toISODate(dayAfterMonth), today), "someday")

  console.log("test-util: all assertions passed")
}

run()
```

- [ ] **Step 2: Run it to confirm it fails**

Run: `node plugin/scripts/test-util.js`
Expected: `Error: Cannot find module '../Util.js'`

- [ ] **Step 3: Implement `Util.js`**

`plugin/Util.js`:

```js
function toISODate(date) {
  var y = date.getFullYear()
  var m = String(date.getMonth() + 1).padStart(2, "0")
  var d = String(date.getDate()).padStart(2, "0")
  return y + "-" + m + "-" + d
}

function parseISODate(str) {
  var parts = String(str || "").split("-")
  if (parts.length !== 3) return null
  var y = parseInt(parts[0], 10)
  var m = parseInt(parts[1], 10)
  var d = parseInt(parts[2], 10)
  if (!y || !m || !d) return null
  return new Date(y, m - 1, d)
}

function startOfISOWeek(date) {
  var day = date.getDay() // 0=Sun..6=Sat
  var diffToMonday = day === 0 ? -6 : 1 - day
  return new Date(date.getFullYear(), date.getMonth(), date.getDate() + diffToMonday)
}

function endOfISOWeek(date) {
  var monday = startOfISOWeek(date)
  return new Date(monday.getFullYear(), monday.getMonth(), monday.getDate() + 6)
}

function endOfMonth(date) {
  return new Date(date.getFullYear(), date.getMonth() + 1, 0)
}

function bucketFor(dueDateStr, today) {
  if (!dueDateStr) return "someday"
  var due = parseISODate(dueDateStr)
  if (!due) return "someday"

  var todayISO = toISODate(today)
  var dueISO = toISODate(due)

  if (dueISO <= todayISO) return "today"
  if (dueISO <= toISODate(endOfISOWeek(today))) return "thisweek"
  if (dueISO <= toISODate(endOfMonth(today))) return "thismonth"
  return "someday"
}

if (typeof module !== "undefined") {
  module.exports = {
    toISODate: toISODate,
    parseISODate: parseISODate,
    startOfISOWeek: startOfISOWeek,
    endOfISOWeek: endOfISOWeek,
    endOfMonth: endOfMonth,
    bucketFor: bucketFor
  }
}
```

- [ ] **Step 4: Run the test to confirm it passes**

Run: `node plugin/scripts/test-util.js`
Expected: `test-util: all assertions passed`

- [ ] **Step 5: Commit**

```bash
git add plugin/Util.js plugin/scripts/test-util.js
git commit -m "$(cat <<'EOF'
Add due-date bucketing logic with a standalone Node test harness

Pure date math (today/thisweek/thismonth/someday), verified outside
QML since no test framework exists in this Quickshell environment.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01QeLfQxs4RoVptycMn9vDnd
EOF
)"
```

---

## Task 3: Todo storage — bucket files, rollover, and archive (`TodoStore.qml`)

**Files:**
- Create: `plugin/TodoStore.qml`

**Interfaces:**
- Consumes: `Util.bucketFor(dueDateStr, today)` from Task 2.
- Produces (used by `TodoPane.qml` in Task 4 and `Main.qml` in Task 7):
  - Properties: `dataDir` (string, settable), `todayTasks`, `thisWeekTasks`, `thisMonthTasks`, `somedayTasks` (each a JS array of `{id, text, dueDate, notes, createdAt, completedAt}`), `loaded` (bool).
  - Signal: `tasksChanged()`.
  - Functions: `addTask(text, dueDate, notes)`, `editDueDate(taskId, dueDate)`, `removeTask(taskId)`, `completeTask(taskId)`.

- [ ] **Step 1: Write `TodoStore.qml`**

```qml
import QtQuick
import Quickshell
import Quickshell.Io
import "Util.js" as Util

QtObject {
  id: root

  property string dataDir: ""
  property var todayTasks: []
  property var thisWeekTasks: []
  property var thisMonthTasks: []
  property var somedayTasks: []
  property bool loaded: false

  property int _pendingBucketLoads: 4
  property string _loadedArchiveMonthKey: ""
  property var _archiveCache: []

  signal tasksChanged()

  readonly property string todayPath: dataDir + "/today.json"
  readonly property string weekPath: dataDir + "/thisweek.json"
  readonly property string monthPath: dataDir + "/thismonth.json"
  readonly property string somedayPath: dataDir + "/someday.json"
  readonly property string archiveDir: dataDir + "/archive"

  function parseList(raw) {
    if (!raw || raw.trim() === "") return []
    try {
      var parsed = JSON.parse(raw)
      return Array.isArray(parsed) ? parsed : []
    } catch (e) {
      console.warn("sebastiangrant.dashboard: failed to parse todo file, treating as empty:", e)
      return []
    }
  }

  function newTaskId() {
    return "t_" + Date.now() + "_" + Math.floor(Math.random() * 10000)
  }

  function allOpenTasks() {
    return root.todayTasks.concat(root.thisWeekTasks, root.thisMonthTasks, root.somedayTasks)
  }

  function currentArchiveMonthKey() {
    var d = new Date()
    return d.getFullYear() + "-" + String(d.getMonth() + 1).padStart(2, "0")
  }

  function archivePathForKey(key) {
    return root.archiveDir + "/" + key + ".json"
  }

  // ---------------------------------------------------------- public API

  function addTask(text, dueDate, notes) {
    var task = {
      id: newTaskId(),
      text: String(text || "").trim(),
      dueDate: dueDate || null,
      notes: notes || "",
      createdAt: new Date().toISOString(),
      completedAt: null
    }
    if (!task.text) return
    rolloverAndWrite(allOpenTasks().concat([task]))
  }

  function editDueDate(taskId, dueDate) {
    var all = allOpenTasks()
    for (var i = 0; i < all.length; i++) {
      if (all[i].id === taskId) { all[i].dueDate = dueDate || null; break }
    }
    rolloverAndWrite(all)
  }

  function removeTask(taskId) {
    rolloverAndWrite(allOpenTasks().filter(function(t) { return t.id !== taskId }))
  }

  function completeTask(taskId) {
    var all = allOpenTasks()
    var remaining = []
    var completed = null
    for (var i = 0; i < all.length; i++) {
      if (all[i].id === taskId) completed = all[i]
      else remaining.push(all[i])
    }
    if (!completed) return
    completed.completedAt = new Date().toISOString()
    appendToArchive(completed)
    rolloverAndWrite(remaining)
  }

  function rollover() {
    rolloverAndWrite(allOpenTasks())
  }

  // --------------------------------------------------------------- internals

  function rolloverAndWrite(tasks) {
    var buckets = { today: [], thisweek: [], thismonth: [], someday: [] }
    var now = new Date()
    for (var i = 0; i < tasks.length; i++) {
      var bucket = Util.bucketFor(tasks[i].dueDate, now)
      buckets[bucket].push(tasks[i])
    }
    root.todayTasks = buckets.today
    root.thisWeekTasks = buckets.thisweek
    root.thisMonthTasks = buckets.thismonth
    root.somedayTasks = buckets.someday
    todayFile.setText(JSON.stringify(buckets.today, null, 2) + "\n")
    weekFile.setText(JSON.stringify(buckets.thisweek, null, 2) + "\n")
    monthFile.setText(JSON.stringify(buckets.thismonth, null, 2) + "\n")
    somedayFile.setText(JSON.stringify(buckets.someday, null, 2) + "\n")
    root.tasksChanged()
  }

  function ensureArchiveLoadedForToday() {
    var key = currentArchiveMonthKey()
    if (key === root._loadedArchiveMonthKey) return
    root._loadedArchiveMonthKey = key
    archiveFile.path = archivePathForKey(key)
    archiveFile.reload()
  }

  function appendToArchive(task) {
    // ensureArchiveLoadedForToday() runs at startup and on every midnight
    // tick (see Main.qml's daily timer), so by the time a completion
    // happens the cache is already for the current month in all
    // realistic cases. A completion landing in the exact instant of a
    // month rollover is an accepted, disclosed edge case (spec: no
    // locking/merge handling for v1).
    root._archiveCache = root._archiveCache.concat([task])
    archiveFile.setText(JSON.stringify(root._archiveCache, null, 2) + "\n")
  }

  // Two independent gates must both clear before the store is allowed to
  // write anything: all four bucket files must have reported a load
  // result (success or failure — either way we know their real content),
  // AND `mkdir -p` must have finished, so a write can't land in a
  // not-yet-created directory. Each bucket FileView's `path` is a live
  // binding to root.dataDir (via todayPath etc.), so it triggers its own
  // load automatically the moment dataDir is set — there is deliberately
  // no second, explicit `.reload()` call here, since that would double-fire
  // per file and let _pendingBucketLoads reach zero before every file's
  // *real* content has actually arrived.
  property bool _dirsReady: false

  function _maybeFinishLoading() {
    if (root.loaded) return
    if (root._pendingBucketLoads > 0) return
    if (!root._dirsReady) return
    root.loaded = true
    rollover()
    ensureArchiveLoadedForToday()
  }

  function _bucketLoadArrived() {
    root._pendingBucketLoads -= 1
    root._maybeFinishLoading()
  }

  property var _ensureDirsProc: Process {
    id: ensureDirsProc
    command: ["mkdir", "-p", root.dataDir, root.archiveDir]
    running: false
    onExited: {
      root._dirsReady = true
      root._maybeFinishLoading()
    }
  }

  function start() {
    if (!root.dataDir) return
    ensureDirsProc.running = true
  }

  onDataDirChanged: start()

  property FileView todayFile: FileView {
    id: todayFile
    watchChanges: true
    atomicWrites: true
    printErrors: false
    path: root.todayPath
    onLoaded: { root.todayTasks = root.parseList(text()); root._bucketLoadArrived() }
    onLoadFailed: { root.todayTasks = []; root._bucketLoadArrived() }
  }

  property FileView weekFile: FileView {
    id: weekFile
    watchChanges: true
    atomicWrites: true
    printErrors: false
    path: root.weekPath
    onLoaded: { root.thisWeekTasks = root.parseList(text()); root._bucketLoadArrived() }
    onLoadFailed: { root.thisWeekTasks = []; root._bucketLoadArrived() }
  }

  property FileView monthFile: FileView {
    id: monthFile
    watchChanges: true
    atomicWrites: true
    printErrors: false
    path: root.monthPath
    onLoaded: { root.thisMonthTasks = root.parseList(text()); root._bucketLoadArrived() }
    onLoadFailed: { root.thisMonthTasks = []; root._bucketLoadArrived() }
  }

  property FileView somedayFile: FileView {
    id: somedayFile
    watchChanges: true
    atomicWrites: true
    printErrors: false
    path: root.somedayPath
    onLoaded: { root.somedayTasks = root.parseList(text()); root._bucketLoadArrived() }
    onLoadFailed: { root.somedayTasks = []; root._bucketLoadArrived() }
  }

  property FileView archiveFile: FileView {
    id: archiveFile
    watchChanges: false
    atomicWrites: true
    printErrors: false
    onLoaded: root._archiveCache = root.parseList(text())
    onLoadFailed: root._archiveCache = []
  }
}
```

Note: `todayPath`/`weekPath`/etc. are declared `readonly property string`
bound to `dataDir`, so they update reactively when `dataDir` is set from
`Main.qml`; the four bucket `FileView`s bind their `path` the same way, so
setting `dataDir` once is enough to point every file at the right place.

- [ ] **Step 2: Manual verification (no shell needed yet — this is pure QML wiring; full behavioral check happens once `Main.qml` wires it up in Task 7)**

Confirm the file has no syntax errors by loading it standalone:

```bash
qmlscene --help >/dev/null 2>&1 && echo "qmlscene available" || echo "qmlscene not available, will verify via omarchy-shell in Task 7"
```

This step only needs to confirm the file is well-formed QML; a full
functional check (add/complete/rollover/archive against real files)
happens in Task 7 once `TodoStore` is wired into the running shell, since
`FileView`/`Process` require the Quickshell runtime, not a generic QML
viewer.

- [ ] **Step 3: Commit**

```bash
git add plugin/TodoStore.qml
git commit -m "$(cat <<'EOF'
Add TodoStore: due-date bucket files, rollover, and monthly archive

Add/edit/remove/complete operate on an in-memory merge of all four
bucket files, rewritten atomically via FileView on every change; a
completed task is appended to the current month's archive file
immediately rather than waiting for the next rollover.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01QeLfQxs4RoVptycMn9vDnd
EOF
)"
```

---

## Task 4: Todo list UI (`TodoSection.qml`, `TodoPane.qml`)

**Files:**
- Create: `plugin/TodoSection.qml`
- Create: `plugin/TodoPane.qml`

**Interfaces:**
- `TodoSection.qml` consumes: `title` (string), `tasks` (array), `store` (a `TodoStore`, Task 3) — calls `store.completeTask(id)` / `store.removeTask(id)` directly from its `Repeater` delegates by referencing the plain property name `store`, which QML resolves up the enclosing component's property scope chain (a standard, well-defined lookup — unlike reaching across sibling `parent` chains, which is fragile and was cut from this plan for that reason).
- `TodoPane.qml` consumes: a `store` property of type `TodoStore` (Task 3) — reads `todayTasks`/`thisWeekTasks`/`thisMonthTasks`/`somedayTasks`, calls `store.addTask(...)`.
- Produces: a `TodoPane` `Item` usable inside `Main.qml` (Task 7), same-directory QML files auto-available with no `import` needed.

- [ ] **Step 1: Write `TodoSection.qml`**

```qml
import QtQuick
import qs.Commons

Column {
  id: root

  property string title: ""
  property var tasks: []
  property var store: null

  width: parent ? parent.width : 0
  spacing: Style.space(4)
  visible: tasks.length > 0

  Text {
    text: root.title + " (" + root.tasks.length + ")"
    color: Color.muted
    font.pixelSize: Style.font.caption
  }

  Repeater {
    model: root.tasks
    delegate: Row {
      width: root.width
      spacing: Style.space(8)

      Rectangle {
        width: Style.space(16)
        height: Style.space(16)
        radius: Style.space(8)
        color: "transparent"
        border.color: Color.foreground
        border.width: 1

        MouseArea {
          anchors.fill: parent
          onClicked: store.completeTask(modelData.id)
        }
      }

      Text {
        width: root.width - Style.space(48)
        text: modelData.text + (modelData.dueDate ? "  ·  " + modelData.dueDate : "")
        color: Color.foreground
        font.pixelSize: Style.font.body
        wrapMode: Text.Wrap
      }

      Text {
        text: "×"
        color: Color.muted
        MouseArea {
          anchors.fill: parent
          onClicked: store.removeTask(modelData.id)
        }
      }
    }
  }
}
```

- [ ] **Step 2: Write `TodoPane.qml`**

```qml
import QtQuick
import QtQuick.Controls
import qs.Commons

Item {
  id: root

  property var store: null

  implicitHeight: column.implicitHeight

  function doAdd() {
    if (!root.store) return
    root.store.addTask(addField.text, dueField.text.trim() || null, "")
    addField.text = ""
    dueField.text = ""
  }

  Column {
    id: column
    width: parent.width
    spacing: Style.space(12)

    Row {
      width: parent.width
      spacing: Style.space(6)

      TextField {
        id: addField
        width: parent.width - dueField.width - addButton.width - Style.space(12)
        placeholderText: "Add a task…"
        color: Color.foreground
        onAccepted: root.doAdd()
      }

      TextField {
        id: dueField
        width: Style.space(96)
        placeholderText: "YYYY-MM-DD"
        color: Color.foreground
      }

      Rectangle {
        id: addButton
        width: Style.space(28)
        height: Style.space(28)
        radius: Style.cornerRadius
        color: Color.accent

        Text { anchors.centerIn: parent; text: "+"; color: Color.background }
        MouseArea { anchors.fill: parent; onClicked: root.doAdd() }
      }
    }

    TodoSection { title: "Today"; tasks: root.store ? root.store.todayTasks : []; store: root.store }
    TodoSection { title: "This Week"; tasks: root.store ? root.store.thisWeekTasks : []; store: root.store }
    TodoSection { title: "This Month"; tasks: root.store ? root.store.thisMonthTasks : []; store: root.store }
    TodoSection { title: "Someday"; tasks: root.store ? root.store.somedayTasks : []; store: root.store }
  }
}
```

- [ ] **Step 3: Defer functional verification to Task 7**

`TodoPane`/`TodoSection` need a live `TodoStore` and the Quickshell
runtime to click-test; wire it into `Main.qml` in Task 7 and verify
add/complete/delete there. Task 7's manual checklist explicitly covers
add/complete/delete through this UI.

- [ ] **Step 4: Commit**

```bash
git add plugin/TodoSection.qml plugin/TodoPane.qml
git commit -m "$(cat <<'EOF'
Add TodoPane/TodoSection: add/complete/delete UI over the due-date buckets

TodoSection takes `store` as a plain property so its Repeater delegates
can call store.completeTask()/removeTask() directly via QML's normal
property scope chain, rather than climbing parent chains.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01QeLfQxs4RoVptycMn9vDnd
EOF
)"
```

---

## Task 5: `.ics` parsing (`IcsParser.js`)

**Files:**
- Create: `plugin/IcsParser.js`
- Create: `plugin/scripts/test-ics-parser.js`

**Interfaces:**
- Produces: `IcsParser.parse(rawIcsText)` → array of `{date: "YYYY-MM-DD", summary: string}`, one entry per non-recurring `VEVENT`. Events whose block contains an `RRULE` line are excluded entirely (Global Constraints).
- Consumed by: `CalendarPane.qml` (Task 6).

- [ ] **Step 1: Write the failing test first**

`plugin/scripts/test-ics-parser.js`:

```js
const assert = require("assert")
const IcsParser = require("../IcsParser.js")

const fixture = [
  "BEGIN:VCALENDAR",
  "VERSION:2.0",
  "BEGIN:VEVENT",
  "UID:1@example.com",
  "DTSTART:20260910T090000Z",
  "SUMMARY:Dentist",
  "END:VEVENT",
  "BEGIN:VEVENT",
  "UID:2@example.com",
  "DTSTART;VALUE=DATE:20260915",
  "SUMMARY:Project deadline",
  "END:VEVENT",
  "BEGIN:VEVENT",
  "UID:3@example.com",
  "DTSTART:20260901T090000Z",
  "RRULE:FREQ=WEEKLY;BYDAY=TU",
  "SUMMARY:Weekly standup",
  "END:VEVENT",
  "BEGIN:VEVENT",
  "UID:4@example.com",
  "SUMMARY:Missing DTSTART, should be skipped",
  "END:VEVENT",
  "END:VCALENDAR"
].join("\r\n")

function run() {
  const events = IcsParser.parse(fixture)

  assert.strictEqual(events.length, 2, "recurring and malformed events must be excluded")

  const dentist = events.find(function(e) { return e.summary === "Dentist" })
  assert.ok(dentist, "non-recurring timed event must be included")
  assert.strictEqual(dentist.date, "2026-09-10")

  const deadline = events.find(function(e) { return e.summary === "Project deadline" })
  assert.ok(deadline, "non-recurring all-day (VALUE=DATE) event must be included")
  assert.strictEqual(deadline.date, "2026-09-15")

  assert.ok(!events.find(function(e) { return e.summary === "Weekly standup" }),
    "event with RRULE must be excluded entirely")
  assert.ok(!events.find(function(e) { return e.summary && e.summary.indexOf("Missing DTSTART") !== -1 }),
    "event without DTSTART must be excluded")

  console.log("test-ics-parser: all assertions passed")
}

run()
```

- [ ] **Step 2: Run it to confirm it fails**

Run: `node plugin/scripts/test-ics-parser.js`
Expected: `Error: Cannot find module '../IcsParser.js'`

- [ ] **Step 3: Implement `IcsParser.js`**

```js
// Minimal RFC5545 subset: unfolds continuation lines, extracts VEVENT
// blocks, reads DTSTART and SUMMARY, and drops any event containing an
// RRULE line entirely (no recurrence expansion — see design spec
// Non-goals). Not a general-purpose ICS library.

function unfold(raw) {
  var lines = String(raw || "").replace(/\r\n/g, "\n").split("\n")
  var out = []
  for (var i = 0; i < lines.length; i++) {
    if ((lines[i].charAt(0) === " " || lines[i].charAt(0) === "\t") && out.length > 0) {
      out[out.length - 1] += lines[i].slice(1)
    } else {
      out.push(lines[i])
    }
  }
  return out
}

function parseDtstartValue(line) {
  // e.g. "DTSTART:20260910T090000Z" or "DTSTART;VALUE=DATE:20260915"
  var colonIndex = line.indexOf(":")
  if (colonIndex === -1) return null
  var value = line.slice(colonIndex + 1).trim()
  var match = value.match(/^(\d{4})(\d{2})(\d{2})/)
  if (!match) return null
  return match[1] + "-" + match[2] + "-" + match[3]
}

function parse(rawIcsText) {
  var lines = unfold(rawIcsText)
  var events = []
  var current = null

  for (var i = 0; i < lines.length; i++) {
    var line = lines[i]
    if (line.indexOf("BEGIN:VEVENT") === 0) {
      current = { date: null, summary: null, recurring: false }
    } else if (line.indexOf("END:VEVENT") === 0) {
      if (current && current.date && current.summary && !current.recurring) {
        events.push({ date: current.date, summary: current.summary })
      }
      current = null
    } else if (current) {
      if (line.indexOf("DTSTART") === 0) {
        current.date = parseDtstartValue(line)
      } else if (line.indexOf("SUMMARY") === 0) {
        var colonIndex = line.indexOf(":")
        current.summary = colonIndex === -1 ? "" : line.slice(colonIndex + 1).trim()
      } else if (line.indexOf("RRULE") === 0) {
        current.recurring = true
      }
    }
  }

  return events
}

if (typeof module !== "undefined") {
  module.exports = { parse: parse }
}
```

- [ ] **Step 4: Run the test to confirm it passes**

Run: `node plugin/scripts/test-ics-parser.js`
Expected: `test-ics-parser: all assertions passed`

- [ ] **Step 5: Commit**

```bash
git add plugin/IcsParser.js plugin/scripts/test-ics-parser.js
git commit -m "$(cat <<'EOF'
Add minimal .ics VEVENT parser (no recurrence expansion)

DTSTART + SUMMARY only; events with RRULE or missing DTSTART are
excluded entirely, per the design spec's v1 scope cut.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01QeLfQxs4RoVptycMn9vDnd
EOF
)"
```

---

## Task 6: Calendar UI (`CalendarPane.qml`)

**Files:**
- Create: `plugin/CalendarPane.qml`

**Interfaces:**
- Consumes: `IcsParser.parse(text)` from Task 5.
- Consumes: an `icsFiles` property (array of absolute path strings) set from `Main.qml` (Task 7).
- Produces: a `CalendarPane` `Item` usable inside `Main.qml`, with an internal `eventsByDate` map (`"YYYY-MM-DD" -> [summary, ...]`) rebuilt whenever any configured `.ics` file loads or changes.

- [ ] **Step 1: Write `CalendarPane.qml`**

```qml
import QtQuick
import QtQml.Models
import Quickshell.Io
import qs.Commons
import "Util.js" as DateUtil
import "IcsParser.js" as IcsParser

// Note: qs.Commons registers its own singleton also named "Util"
// (Commons/Util.qml, per its qmldir) — importing it as a bare "Util"
// alias here would collide, so this file's own Util.js (date bucketing)
// is aliased "DateUtil" instead. Files that don't import qs.Commons
// (TodoStore.qml) keep the plain "Util" alias.

Item {
  id: root

  property var icsFiles: []
  property var eventsByDate: ({})
  property var _eventsBySource: ({})

  property var viewMonth: new Date().getMonth()
  property var viewYear: new Date().getFullYear()
  property string selectedDate: DateUtil.toISODate(new Date())

  implicitHeight: column.implicitHeight

  function mergeIcsEvents(sourcePath, events) {
    var bySource = {}
    for (var k in root._eventsBySource) bySource[k] = root._eventsBySource[k]
    bySource[sourcePath] = events
    root._eventsBySource = bySource

    var merged = {}
    for (var src in bySource) {
      var list = bySource[src]
      for (var i = 0; i < list.length; i++) {
        var date = list[i].date
        if (!merged[date]) merged[date] = []
        merged[date].push(list[i].summary)
      }
    }
    root.eventsByDate = merged
  }

  Instantiator {
    model: root.icsFiles
    delegate: FileView {
      id: icsFile
      required property string modelData
      path: modelData
      watchChanges: true
      printErrors: false
      onLoaded: root.mergeIcsEvents(modelData, IcsParser.parse(text()))
      onLoadFailed: root.mergeIcsEvents(modelData, [])
    }
  }

  function daysInGrid() {
    var firstOfMonth = new Date(root.viewYear, root.viewMonth, 1)
    var gridStart = DateUtil.startOfISOWeek(firstOfMonth)
    var days = []
    for (var i = 0; i < 42; i++) {
      days.push(new Date(gridStart.getFullYear(), gridStart.getMonth(), gridStart.getDate() + i))
    }
    return days
  }

  Column {
    id: column
    width: parent.width
    spacing: Style.space(8)

    Row {
      width: parent.width
      spacing: Style.space(8)

      Text {
        text: "‹"
        color: Color.foreground
        MouseArea {
          anchors.fill: parent
          onClicked: {
            var d = new Date(root.viewYear, root.viewMonth - 1, 1)
            root.viewYear = d.getFullYear()
            root.viewMonth = d.getMonth()
          }
        }
      }

      Text {
        width: parent.width - Style.space(48)
        horizontalAlignment: Text.AlignHCenter
        text: Qt.formatDate(new Date(root.viewYear, root.viewMonth, 1), "MMMM yyyy")
        color: Color.foreground
        font.pixelSize: Style.font.title
      }

      Text {
        text: "›"
        color: Color.foreground
        MouseArea {
          anchors.fill: parent
          onClicked: {
            var d = new Date(root.viewYear, root.viewMonth + 1, 1)
            root.viewYear = d.getFullYear()
            root.viewMonth = d.getMonth()
          }
        }
      }
    }

    Grid {
      width: parent.width
      columns: 7
      rowSpacing: Style.space(4)
      columnSpacing: Style.space(4)

      Repeater {
        model: root.daysInGrid()
        delegate: Rectangle {
          width: (column.width - Style.space(24)) / 7
          height: width
          radius: Style.cornerRadius
          property string dateStr: DateUtil.toISODate(modelData)
          property bool inMonth: modelData.getMonth() === root.viewMonth
          property bool isToday: dateStr === DateUtil.toISODate(new Date())
          property bool hasEvents: !!root.eventsByDate[dateStr] && root.eventsByDate[dateStr].length > 0
          color: dateStr === root.selectedDate ? Color.accent
            : (isToday ? Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.25) : "transparent")

          Text {
            anchors.centerIn: parent
            text: String(modelData.getDate())
            color: inMonth ? Color.foreground : Color.muted
            font.pixelSize: Style.font.bodySmall
          }

          Rectangle {
            visible: hasEvents
            width: Style.space(4)
            height: Style.space(4)
            radius: Style.space(2)
            color: Color.urgent
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: Style.space(2)
          }

          MouseArea {
            anchors.fill: parent
            onClicked: root.selectedDate = dateStr
          }
        }
      }
    }

    Column {
      width: parent.width
      spacing: Style.space(2)
      visible: (root.eventsByDate[root.selectedDate] || []).length > 0

      Text {
        text: root.selectedDate
        color: Color.muted
        font.pixelSize: Style.font.caption
      }

      Repeater {
        model: root.eventsByDate[root.selectedDate] || []
        delegate: Text {
          width: column.width
          text: "• " + modelData
          color: Color.foreground
          font.pixelSize: Style.font.bodySmall
          wrapMode: Text.Wrap
        }
      }
    }
  }
}
```

- [ ] **Step 2: Defer functional verification to Task 7**

Like `TodoPane`, this needs the live Quickshell runtime (`FileView`,
`Instantiator`) to test against a real `.ics` file. Task 7's manual
checklist covers pointing `icsFiles` at a real file and at a
deliberately malformed one.

- [ ] **Step 3: Commit**

```bash
git add plugin/CalendarPane.qml
git commit -m "$(cat <<'EOF'
Add CalendarPane: month grid with .ics event dots and day list

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01QeLfQxs4RoVptycMn9vDnd
EOF
)"
```

---

## Task 7: Wire everything into `Main.qml` — config, monitor targeting, docked/floating, IPC toggle

**Files:**
- Modify: `plugin/Main.qml` (replacing Task 1's smoke-test body)

**Interfaces:**
- Consumes: `TodoStore` (Task 3), `TodoPane` (Task 4), `CalendarPane` (Task 6).
- Produces: the finished plugin surface, including the `IpcHandler` target `sebastiangrant.dashboard` with a `toggleMode()` function, callable via `omarchy-shell sebastiangrant.dashboard toggleMode`.

- [ ] **Step 1: Replace `plugin/Main.qml`**

```qml
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons

Item {
  id: root

  // Injected by shell.qml's ensureService() for every "service"-kind
  // plugin instance (see PluginRegistry / shell.qml ensureService, read
  // during design); manifest.__sourceDir is the plugin's own directory,
  // stamped on by PluginRegistry when it scans manifest.json. Declaring
  // the property is enough for the host to fill it in — no explicit
  // wiring needed on this end.
  property var manifest: null

  readonly property string home: Quickshell.env("HOME")
  readonly property string pluginDir: (root.manifest && root.manifest.__sourceDir) || ""

  property var config: ({
    monitor: "",
    mode: "floating",
    width: 340,
    dataDir: "~/.local/share/sebastiangrant.dashboard",
    icsFiles: []
  })
  property string mode: "floating"
  property bool configLoaded: false

  function expandHome(p) {
    var s = String(p || "")
    if (s.charAt(0) === "~") return root.home + s.slice(1)
    return s
  }

  function applyConfig(parsed) {
    var merged = {
      monitor: (parsed && parsed.monitor) || "",
      mode: (parsed && parsed.mode) || "floating",
      width: (parsed && parsed.width) || 340,
      dataDir: (parsed && parsed.dataDir) || "~/.local/share/sebastiangrant.dashboard",
      icsFiles: (parsed && Array.isArray(parsed.icsFiles)) ? parsed.icsFiles : []
    }
    root.config = merged
    root.mode = merged.mode
    root.configLoaded = true
    todoStore.dataDir = root.expandHome(merged.dataDir)
  }

  FileView {
    id: configFile
    // Empty until `manifest` is injected; the path binding re-evaluates
    // (and Quickshell (re)resolves the file) once pluginDir is non-empty.
    path: root.pluginDir ? root.pluginDir + "/config.json" : ""
    watchChanges: true
    printErrors: false
    onLoaded: {
      try {
        root.applyConfig(JSON.parse(text()))
      } catch (e) {
        console.warn("sebastiangrant.dashboard: config.json malformed, using defaults:", e)
        root.applyConfig(null)
      }
    }
    onLoadFailed: root.applyConfig(null)
  }

  TodoStore {
    id: todoStore
  }

  readonly property var targetScreens: {
    if (!root.configLoaded || Quickshell.screens.length === 0) return []
    var matches = Quickshell.screens.filter(function(s) { return s.name === root.config.monitor })
    if (matches.length > 0) return matches
    console.warn("sebastiangrant.dashboard: monitor '" + root.config.monitor
      + "' not found, falling back to first available screen")
    return [Quickshell.screens[0]]
  }

  Timer {
    id: midnightTimer
    repeat: false
    running: root.configLoaded
    interval: {
      var now = new Date()
      var nextMidnight = new Date(now.getFullYear(), now.getMonth(), now.getDate() + 1, 0, 1, 0)
      return nextMidnight.getTime() - now.getTime()
    }
    onTriggered: {
      todoStore.rollover()
      todoStore.ensureArchiveLoadedForToday()
      interval = 24 * 60 * 60 * 1000
      restart()
    }
  }

  IpcHandler {
    target: "sebastiangrant.dashboard"

    function toggleMode(): void {
      root.mode = root.mode === "docked" ? "floating" : "docked"
    }
  }

  Variants {
    model: root.targetScreens

    PanelWindow {
      id: panel
      required property var modelData
      screen: modelData

      anchors { top: true; bottom: true; right: true }
      implicitWidth: root.config.width
      color: Color.background

      WlrLayershell.namespace: "sebastiangrant-dashboard"
      WlrLayershell.layer: WlrLayer.Top
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
      exclusionMode: root.mode === "docked" ? ExclusionMode.Auto : ExclusionMode.Ignore

      Flickable {
        anchors.fill: parent
        anchors.margins: Style.space(12)
        contentWidth: width
        contentHeight: content.implicitHeight
        clip: true

        Column {
          id: content
          width: parent.width
          spacing: Style.space(20)

          CalendarPane {
            width: parent.width
            icsFiles: {
              var list = []
              for (var i = 0; i < root.config.icsFiles.length; i++) {
                list.push(root.expandHome(root.config.icsFiles[i]))
              }
              return list
            }
          }

          TodoPane {
            width: parent.width
            store: todoStore
          }
        }
      }
    }
  }
}
```

`TodoStore`, `TodoPane`, and `CalendarPane` need no `import` statement:
same-directory `.qml` files are implicitly available as QML types named
after their filename, which is why `Main.qml` can write `TodoStore { }`,
`TodoPane { }`, and `CalendarPane { }` directly.

- [ ] **Step 2: Reload and manually verify (this is the real functional gate for Tasks 3, 4, 6, and 7 together)**

```bash
omarchy restart shell
```

Verification checklist — work through all of these against the running
shell, editing `plugin/config.json` between checks as needed (it
hot-reloads via the watched `FileView`):

1. Fresh-start check: `rm -rf ~/.local/share/sebastiangrant.dashboard`
   (only if that path doesn't already hold data you want — it's a fresh
   test directory on first install), then `omarchy restart shell`.
   Confirm the directory, its four bucket JSON files, and `archive/` all
   get created with no warnings in the log — this exercises the
   mkdir-vs-file-load startup sequencing in `TodoStore.qml` directly.
2. Panel appears on the monitor named in `config.json`'s `monitor` field
   (get real names via `hyprctl monitors -j`), anchored to the right edge.
3. Set `mode` to `"docked"` in `config.json`, save: confirm (via
   `hyprctl clients` or just visually) that windows on that monitor tile
   around the panel's width rather than going underneath it.
4. Set `mode` to `"floating"`, save: confirm windows now go edge-to-edge
   underneath the panel.
5. Run `omarchy-shell sebastiangrant.dashboard toggleMode` from a
   terminal: confirm the mode flips live without touching `config.json`,
   and that `config.json`'s `mode` value is unchanged on disk afterward.
6. Set `monitor` in `config.json` to a name that doesn't exist (e.g.
   `"NOPE-1"`), save: confirm the panel falls back to the first available
   screen and a `monitor '...' not found` warning appears in the shell's
   log output. Restore the real monitor name afterward.
7. In the todo UI: add a task with no due date — confirm it appears
   under "Someday". Add one with today's date (`YYYY-MM-DD`) — confirm
   it appears under "Today". Inspect
   `~/.local/share/sebastiangrant.dashboard/someday.json` and `today.json`
   directly to confirm the writes landed.
8. Click a task's checkbox to complete it: confirm it disappears from
   its bucket file and appears in
   `~/.local/share/sebastiangrant.dashboard/archive/<this-year-month>.json`
   with `completedAt` set.
9. Click a task's `×` to delete it (without completing): confirm it's
   gone from its bucket file and does **not** appear in any archive file.
10. Point `icsFiles` in `config.json` at a real `.ics` file (export one
    from any calendar app, or hand-write one using the fixture shape from
    `plugin/scripts/test-ics-parser.js`): confirm a dot appears on the
    right day in the grid and clicking that day lists the event summary.
11. Point `icsFiles` at a path that doesn't exist: confirm the plugin
    still loads and the todo/calendar panes still work (no crash, at most
    a warning in the log).
12. Confirm panel colors track the active theme: run `omarchy theme set
    <a-different-installed-theme>`, then confirm the panel's background
    and text colors change without restarting the shell.

- [ ] **Step 3: Commit**

```bash
git add plugin/Main.qml
git commit -m "$(cat <<'EOF'
Wire TodoStore/TodoPane/CalendarPane into Main.qml

Adds config.json loading with defaults, monitor targeting with
fallback, docked/floating exclusionMode driven by config or the
toggleMode IPC call, and a daily rollover/archive-refresh timer.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01QeLfQxs4RoVptycMn9vDnd
EOF
)"
```

---

## Task 8: Hyprland keybind for the mode toggle, README, final pass

**Files:**
- Modify: `~/.config/hypr/bindings.lua` (via the `omarchy` skill — this is a Hyprland config edit and must go through that skill's conventions, not a raw text edit)
- Create: `README.md`

**Interfaces:** None — this task is user-facing polish, not code other tasks depend on.

- [ ] **Step 1: Add a keybind for the live mode toggle**

Invoke the `omarchy` skill to add a keybinding (ask the user which key
combination they want, since this is a personal keybinding choice, not
specified anywhere in the spec) that runs:

```bash
omarchy-shell sebastiangrant.dashboard toggleMode
```

Follow `hyprland.md`'s guidance on where/how to add a binding in
`~/.config/hypr/bindings.lua`, then validate with `hyprctl reload` and
`hyprctl configerrors`.

- [ ] **Step 2: Write `README.md`**

```markdown
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
```

- [ ] **Step 3: Commit**

```bash
git add README.md
git commit -m "$(cat <<'EOF'
Add README and Hyprland keybind for the docked/floating toggle

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01QeLfQxs4RoVptycMn9vDnd
EOF
)"
```
