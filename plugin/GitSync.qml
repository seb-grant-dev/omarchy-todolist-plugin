import QtQuick
import Quickshell.Io

// Periodically commits and pushes dataDir if it's a git repo. Opt-in via
// config's `gitSync: true` — the plugin never runs `git init`, `git remote
// add`, or handles auth/SSH-agent/credential prompts; the repo and its
// remote must already be set up by hand (see README's "Git sync" section).
QtObject {
  id: root

  property string dataDir: ""
  property bool enabled: false
  property int intervalMinutes: 15

  function start() {
    if (!root.enabled || !root.dataDir) return
    Qt.callLater(function() { root._runSync() })
  }

  function _runSync() {
    if (!root.enabled || !root.dataDir) return
    if (syncProc.running) return // previous cycle still in flight; skip this tick
    syncProc.running = true
  }

  onEnabledChanged: root.start()
  onDataDirChanged: root.start()

  property Timer timer: Timer {
    id: timer
    // Minimum 1 minute so a stray 0/negative config value can't spin the
    // sync loop continuously.
    interval: Math.max(1, root.intervalMinutes) * 60 * 1000
    running: root.enabled && !!root.dataDir
    repeat: true
    triggeredOnStart: false
    onTriggered: root._runSync()
  }

  // Warned-once guards for the two "not really an error" exit codes below,
  // so a repo with no remote (or a misconfigured non-repo dataDir) doesn't
  // spam a warning every single cycle.
  property bool _warnedNotRepo: false
  property bool _warnedNoRemote: false

  readonly property int _exitNotRepo: 3
  readonly property int _exitNoRemote: 2

  property Process syncProc: Process {
    id: syncProc
    command: ["bash", "-c", root._script()]
    running: false
    onExited: (exitCode, exitStatus) => {
      if (exitCode === 0) {
        // success — nothing to warn about
      } else if (exitCode === root._exitNotRepo) {
        if (!root._warnedNotRepo) {
          root._warnedNotRepo = true
          console.warn("sebastiangrant.dashboard: gitSync is enabled but dataDir="
            + root.dataDir + " is not a git repo — disable gitSync or `git init` it yourself")
        }
      } else if (exitCode === root._exitNoRemote) {
        if (!root._warnedNoRemote) {
          root._warnedNoRemote = true
          console.warn("sebastiangrant.dashboard: dataDir=" + root.dataDir
            + " has no 'origin' remote — committing locally only, never pushing")
        }
      } else {
        console.warn("sebastiangrant.dashboard: git sync failed (exit code " + exitCode
          + ") for dataDir=" + root.dataDir + " — will retry next cycle")
      }
    }
  }

  // Single bash script per tick, in this order:
  //   1. Exit _exitNotRepo if dataDir isn't a git repo.
  //   2. Stage and commit any local changes first, so the working tree is
  //      clean before the rebase below (a dirty tree would abort it).
  //   3. Exit _exitNoRemote if there's no `origin` remote configured — a
  //      repo with no remote is committed to locally only.
  //   4. Pull --rebase (with autostash as a belt-and-braces guard even
  //      though the tree is already clean) to bring in changes from other
  //      machines, then push. A rebase conflict aborts the rebase and
  //      exits non-zero, leaving the repo in a clean (non-mid-rebase)
  //      state so the next cycle can try again cleanly.
  function _script() {
    var dir = root.dataDir
    return "cd " + root._shellQuote(dir) + " || exit 1\n"
      + "git rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit " + root._exitNotRepo + "\n"
      + "git add -A || exit 1\n"
      + "git diff --cached --quiet || git commit -m \"Auto-sync: $(date -Iseconds)\" || exit 1\n"
      + "git remote get-url origin >/dev/null 2>&1 || exit " + root._exitNoRemote + "\n"
      + "branch=$(git rev-parse --abbrev-ref HEAD)\n"
      + "if ! git pull --rebase --autostash origin \"$branch\"; then\n"
      + "  git rebase --abort >/dev/null 2>&1\n"
      + "  exit 1\n"
      + "fi\n"
      + "git push origin \"$branch\"\n"
  }

  // Minimal single-quote shell escaping: close the quote, emit an escaped
  // single quote, reopen — the standard POSIX-shell idiom.
  function _shellQuote(s) {
    return "'" + String(s).split("'").join("'\\''") + "'"
  }
}
