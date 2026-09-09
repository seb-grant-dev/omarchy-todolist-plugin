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
    if (!root.loaded) return
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
    if (!root.loaded) return
    var all = allOpenTasks()
    for (var i = 0; i < all.length; i++) {
      if (all[i].id === taskId) { all[i].dueDate = dueDate || null; break }
    }
    rolloverAndWrite(all)
  }

  function removeTask(taskId) {
    if (!root.loaded) return
    rolloverAndWrite(allOpenTasks().filter(function(t) { return t.id !== taskId }))
  }

  function completeTask(taskId) {
    if (!root.loaded) return
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
