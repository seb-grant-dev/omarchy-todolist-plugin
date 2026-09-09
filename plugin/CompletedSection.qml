import QtQuick
import qs.Commons

Column {
  id: root

  property var tasks: [] // pre-sorted newest-first by TodoStore
  property var store: null

  readonly property int collapsedCount: 5

  property bool expanded: false
  readonly property var visibleTasks: root.expanded ? root.tasks : root.tasks.slice(0, root.collapsedCount)

  width: parent ? parent.width : 0
  spacing: Style.space(4)
  visible: tasks.length > 0

  Text {
    text: "Recently Completed (" + root.tasks.length + ")"
    color: Color.muted
    font.pixelSize: Style.font.caption
  }

  Repeater {
    model: root.visibleTasks
    delegate: Row {
      width: root.width
      spacing: Style.space(8)

      Rectangle {
        width: Style.space(16)
        height: Style.space(16)
        radius: Style.space(8)
        color: Color.foreground
        border.color: Color.foreground
        border.width: 1

        Text {
          anchors.centerIn: parent
          text: "✓"
          color: Color.background
          font.pixelSize: Style.font.caption
        }

        MouseArea {
          anchors.fill: parent
          onClicked: store.uncompleteTask(modelData.id)
        }
      }

      Text {
        width: root.width - Style.space(24)
        text: modelData.text
        color: Color.muted
        font.pixelSize: Style.font.body
        font.strikeout: true
        wrapMode: Text.Wrap
      }
    }
  }

  Text {
    visible: root.tasks.length > root.collapsedCount
    text: root.expanded ? "Show less" : "Show more"
    color: Color.accent
    font.pixelSize: Style.font.caption

    MouseArea {
      anchors.fill: parent
      onClicked: root.expanded = !root.expanded
    }
  }
}
