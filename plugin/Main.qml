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
