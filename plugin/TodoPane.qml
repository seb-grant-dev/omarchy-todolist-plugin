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
