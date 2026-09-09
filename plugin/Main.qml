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
