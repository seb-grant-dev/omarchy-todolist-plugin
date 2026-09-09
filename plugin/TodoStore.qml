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
  property bool _archiveLoaded: false
  property var _parseFailedBuckets: ({ today: false, thisweek: false, thismonth: false, someday: false })

  signal tasksChanged()

  readonly property string todayPath: dataDir + "/today.json"
  readonly property string weekPath: dataDir + "/thisweek.json"
  readonly property string monthPath: dataDir + "/thismonth.json"
  readonly property string somedayPath: dataDir + "/someday.json"
  readonly property string archiveDir: dataDir + "/archive"

  // bucketName is optional; when given, a JSON.parse failure is recorded in
  // _parseFailedBuckets so the very next startup rollover can avoid writing
  // an empty array over a file that was merely mid-sync-write or hand-edited
  // invalid (see Fix 3 in the final-fix-report). Callers that don't care
  // about that (e.g. archive parsing) simply omit the second argument.
  function parseList(raw, bucketName) {
    if (!raw || raw.trim() === "") return []
    try {
      var parsed = JSON.parse(raw)
      return Array.isArray(parsed) ? parsed : []
    } catch (e) {
      console.warn("sebastiangrant.dashboard: failed to parse todo file, treating as empty:", e)
      if (bucketName) root._parseFailedBuckets[bucketName] = true
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
    // Also requires the archive to have actually finished its own async
    // load (see Fix 6 in the final-fix-report): ensureArchiveLoadedForToday()
    // kicks off a fresh archive read any time the month key changes
    // (including at startup), and appendToArchive() below would otherwise
    // be able to write the just-initialized (empty) _archiveCache over that
    // month's real, not-yet-loaded archive content in the narrow window
    // before the read completes.
    if (!root.loaded || !root._archiveLoaded) return
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

  // skipBuckets (optional) maps bucket keys ("today"/"thisweek"/"thismonth"/
  // "someday") to true for buckets whose on-disk file must NOT be rewritten
  // on this call. Only ever passed by _maybeFinishLoading(), for the very
  // first rollover after startup, to protect a bucket file that failed to
  // parse (see Fix 3) from being silently overwritten with an empty array
  // before the user has done anything. Every other caller (addTask,
  // completeTask, the midnight Timer in Main.qml, etc.) calls rollover()
  // with no argument, which writes all four files normally — once the user
  // has taken any real action, or once they've manually fixed the file and
  // restarted, writes proceed as usual.
  function rollover(skipBuckets) {
    if (!root.loaded) return
    rolloverAndWrite(allOpenTasks(), skipBuckets)
  }

  // --------------------------------------------------------------- internals

  function rolloverAndWrite(tasks, skipBuckets) {
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
    var skip = skipBuckets || {}
    if (!skip.today) todayFile.setText(JSON.stringify(buckets.today, null, 2) + "\n")
    if (!skip.thisweek) weekFile.setText(JSON.stringify(buckets.thisweek, null, 2) + "\n")
    if (!skip.thismonth) monthFile.setText(JSON.stringify(buckets.thismonth, null, 2) + "\n")
    if (!skip.someday) somedayFile.setText(JSON.stringify(buckets.someday, null, 2) + "\n")
    root.tasksChanged()
  }

  function ensureArchiveLoadedForToday() {
    var key = currentArchiveMonthKey()
    if (key === root._loadedArchiveMonthKey) return
    root._loadedArchiveMonthKey = key
    root._archiveLoaded = false
    archiveFile.path = archivePathForKey(key)
    archiveFile.reload()
  }

  function appendToArchive(task) {
    // ensureArchiveLoadedForToday() runs at startup and on every midnight
    // tick (see Main.qml's daily timer), so by the time a completion
    // happens the cache is already for the current month in all
    // realistic cases. A completion landing in the exact instant of a
    // month rollover is an accepted, disclosed edge case (spec: no
    // locking/merge handling for v1). The narrower startup race (a
    // completion landing before the *initial* archive load finishes) is
    // now closed by the `_archiveLoaded` guard in completeTask() (Fix 6).
    root._archiveCache = root._archiveCache.concat([task])
    archiveFile.setText(JSON.stringify(root._archiveCache, null, 2) + "\n")
  }

  // Two independent gates must both clear before the store is allowed to
  // write anything: all four bucket files must have reported a load
  // result (success or failure — either way we know their real content,
  // since each bucket FileView's `path` only ever points at a real,
  // resolved dataDir-relative path — see below), AND `mkdir -p` must have
  // finished, so a write can't land in a not-yet-created directory. Each
  // bucket FileView's `path` is `root.dataDir ? root.<x>Path : ""` — a
  // live binding that only resolves to a real path once dataDir is
  // actually set, and is "" (which FileView treats as "nothing to load",
  // firing neither onLoaded nor onLoadFailed — verified empirically, see
  // final-fix-report) before that. This closes the startup race where the
  // degenerate `dataDir === ""` paths (e.g. "/today.json") used to load-fail
  // immediately and satisfy this gate long before the real dataDir/paths
  // were ever set, leaving only _dirsReady to guard the first write against
  // racing the real bucket loads. There is deliberately no explicit
  // `.reload()` call here for the bucket files — the path binding itself
  // triggers the load automatically the moment it resolves to a real path,
  // and an explicit reload would double-fire per file.
  property bool _dirsReady: false

  function _maybeFinishLoading() {
    if (root.loaded) return
    if (root._pendingBucketLoads > 0) return
    if (!root._dirsReady) return
    root.loaded = true
    rollover(root._parseFailedBuckets)
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
    onExited: (exitCode, exitStatus) => {
      if (exitCode !== 0) {
        console.warn("sebastiangrant.dashboard: mkdir -p failed (exit code " + exitCode
          + ") for dataDir=" + root.dataDir + " archiveDir=" + root.archiveDir
          + " — storage may be unwritable or unavailable")
      }
      root._dirsReady = true
      root._maybeFinishLoading()
    }
  }

  function start() {
    if (!root.dataDir) return
    // Re-arm both startup gates every time dataDir is (re)set — not
    // reachable today since Main.qml only sets dataDir once, but this
    // makes the invariant hold for real rather than relying on dataDir
    // never changing again.
    root._pendingBucketLoads = 4
    root._dirsReady = false
    root.loaded = false
    root._parseFailedBuckets = { today: false, thisweek: false, thismonth: false, someday: false }
    // Deferred: dataDir is set from an async callback (Main.qml's config
    // FileView.onLoaded), and reading the derived root.archiveDir binding
    // synchronously within that same tick can observe a stale
    // not-yet-recomputed value, producing a `mkdir -p <dataDir> <stale>`
    // command that fails to create the archive directory. Qt.callLater
    // pushes the run to the next event-loop turn, by which point QML has
    // settled every dependent binding, so the Process's `command` array
    // reads the correct, final dataDir/archiveDir pair.
    Qt.callLater(function() {
      ensureDirsProc.running = true
    })
  }

  onDataDirChanged: start()

  property FileView todayFile: FileView {
    id: todayFile
    watchChanges: true
    atomicWrites: true
    printErrors: false
    path: root.dataDir ? root.todayPath : ""
    onLoaded: { root.todayTasks = root.parseList(text(), "today"); root._bucketLoadArrived() }
    onLoadFailed: { root.todayTasks = []; root._bucketLoadArrived() }
    onSaveFailed: (error) => console.warn("sebastiangrant.dashboard: failed to save today.json: "
      + FileViewError.toString(error))
  }

  property FileView weekFile: FileView {
    id: weekFile
    watchChanges: true
    atomicWrites: true
    printErrors: false
    path: root.dataDir ? root.weekPath : ""
    onLoaded: { root.thisWeekTasks = root.parseList(text(), "thisweek"); root._bucketLoadArrived() }
    onLoadFailed: { root.thisWeekTasks = []; root._bucketLoadArrived() }
    onSaveFailed: (error) => console.warn("sebastiangrant.dashboard: failed to save thisweek.json: "
      + FileViewError.toString(error))
  }

  property FileView monthFile: FileView {
    id: monthFile
    watchChanges: true
    atomicWrites: true
    printErrors: false
    path: root.dataDir ? root.monthPath : ""
    onLoaded: { root.thisMonthTasks = root.parseList(text(), "thismonth"); root._bucketLoadArrived() }
    onLoadFailed: { root.thisMonthTasks = []; root._bucketLoadArrived() }
    onSaveFailed: (error) => console.warn("sebastiangrant.dashboard: failed to save thismonth.json: "
      + FileViewError.toString(error))
  }

  property FileView somedayFile: FileView {
    id: somedayFile
    watchChanges: true
    atomicWrites: true
    printErrors: false
    path: root.dataDir ? root.somedayPath : ""
    onLoaded: { root.somedayTasks = root.parseList(text(), "someday"); root._bucketLoadArrived() }
    onLoadFailed: { root.somedayTasks = []; root._bucketLoadArrived() }
    onSaveFailed: (error) => console.warn("sebastiangrant.dashboard: failed to save someday.json: "
      + FileViewError.toString(error))
  }

  property FileView archiveFile: FileView {
    id: archiveFile
    watchChanges: false
    atomicWrites: true
    printErrors: false
    onLoaded: { root._archiveCache = root.parseList(text()); root._archiveLoaded = true }
    onLoadFailed: { root._archiveCache = []; root._archiveLoaded = true }
    onSaveFailed: (error) => console.warn("sebastiangrant.dashboard: failed to save archive file: "
      + FileViewError.toString(error))
  }
}
