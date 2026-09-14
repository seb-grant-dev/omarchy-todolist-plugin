import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons

Item {
  id: root

  // Injected by shell.qml's ensureService() for every "service"-kind
  // plugin instance. Declaring the property is enough for the host to fill
  // it in — no explicit wiring needed on this end.
  property var manifest: null

  readonly property string home: Quickshell.env("HOME")

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

  readonly property var modeCycle: ["docked", "floating", "hidden"]

  function applyConfig(parsed) {
    if (parsed && parsed.mode !== undefined && root.modeCycle.indexOf(parsed.mode) === -1) {
      console.warn("sebastiangrant.dashboard: config.json has unrecognized mode '" + parsed.mode
        + "', expected \"docked\", \"floating\" or \"hidden\" — only \"docked\" is checked explicitly,"
        + " so this will behave as floating")
    }
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
    // Resolved relative to this QML file's own location, so it needs no
    // host-provided path — the shell's publicPluginManifest() strips
    // manifest.__sourceDir before handing the manifest to third-party
    // plugins (it's private to PluginRegistry's own entry-point resolution),
    // so that can no longer be used to find sibling files like this one.
    path: Qt.resolvedUrl("config.json")
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
      for (var i = 0; i < calendarPanes.length; i++) calendarPanes[i].refreshToday()
      interval = 24 * 60 * 60 * 1000
      restart()
    }
  }

  // One CalendarPane is instantiated per targeted screen (see the Variants
  // below); collect them so the midnight timer above can push a fresh
  // "today" into every instance's todayISO (see CalendarPane.qml's isToday
  // fix — a plain `new Date()` in a delegate binding is evaluated once at
  // creation and would otherwise go stale every night).
  property var calendarPanes: []

  IpcHandler {
    target: "sebastiangrant.dashboard"

    function toggleMode(): void {
      var idx = root.modeCycle.indexOf(root.mode)
      root.mode = root.modeCycle[(idx + 1) % root.modeCycle.length]
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
      visible: root.mode !== "hidden"

      WlrLayershell.namespace: "sebastiangrant-dashboard"
      WlrLayershell.layer: WlrLayer.Top
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
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
            id: calendarPane
            width: parent.width
            icsFiles: {
              var list = []
              for (var i = 0; i < root.config.icsFiles.length; i++) {
                list.push(root.expandHome(root.config.icsFiles[i]))
              }
              return list
            }
            Component.onCompleted: root.calendarPanes = root.calendarPanes.concat([calendarPane])
            Component.onDestruction: root.calendarPanes = root.calendarPanes.filter(function(p) { return p !== calendarPane })
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
