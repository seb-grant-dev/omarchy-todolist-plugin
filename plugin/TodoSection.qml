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
