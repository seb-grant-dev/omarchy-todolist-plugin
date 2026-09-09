import QtQuick
import QtQuick.Controls
import qs.Commons
import "Util.js" as DateUtil

Item {
  id: root

  property var store: null

  implicitHeight: column.implicitHeight

  // The system locale's own short-date pattern (day/month order and
  // separators as the OS reports them), but with the year forced to 4
  // digits — Locale.ShortFormat defaults to a 2-digit year, which is
  // ambiguous for a task due date.
  function localeDatePattern() {
    var fmt = Qt.locale().dateFormat(Locale.ShortFormat)
    return fmt.replace(/y{1,4}/, "yyyy")
  }

  // Returns {ok: true, iso: "YYYY-MM-DD"|null} for empty/valid input,
  // or {ok: false} if non-empty text doesn't parse as a valid date in
  // the locale pattern above. Storage format (ISO) is unchanged by this.
  function parseDueDate(text) {
    var trimmed = String(text || "").trim()
    if (!trimmed) return { ok: true, iso: null }
    var parsed = Date.fromLocaleDateString(Qt.locale(), trimmed, root.localeDatePattern())
    if (isNaN(parsed.getTime())) return { ok: false, iso: null }
    return { ok: true, iso: DateUtil.toISODate(parsed) }
  }

  function doAdd() {
    // Guard on store.loaded too (not just root.store being non-null):
    // TodoStore.addTask() itself no-ops before startup finishes, and
    // clearing the fields unconditionally in that window would silently
    // discard whatever the user typed with zero feedback.
    if (!root.store || !root.store.loaded) return

    var due = root.parseDueDate(dueField.text)
    if (!due.ok) return // invalid date typed — leave both fields as-is so the user can fix it

    root.store.addTask(addField.text, due.iso, "")
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
        font.pixelSize: Style.font.bodySmall
        leftPadding: Style.space(8)
        rightPadding: Style.space(8)
        topPadding: Style.space(6)
        bottomPadding: Style.space(6)
        background: Rectangle {
          // A subtle lift over the panel's own background (same 0.08
          // foreground-tint the shell itself uses for menu.selectedBackground)
          // rather than Color.background, which would be invisible against
          // the panel behind it.
          color: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.08)
          radius: Math.max(Style.cornerRadius, Style.space(6))
          border.color: Color.muted
          border.width: 1
        }
        onAccepted: root.doAdd()
      }

      TextField {
        id: dueField
        width: Style.space(96)
        placeholderText: root.localeDatePattern().toUpperCase()
        color: Color.foreground
        font.pixelSize: Style.font.bodySmall
        leftPadding: Style.space(8)
        rightPadding: Style.space(8)
        topPadding: Style.space(6)
        bottomPadding: Style.space(6)
        background: Rectangle {
          color: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.08)
          radius: Math.max(Style.cornerRadius, Style.space(6))
          border.color: Color.muted
          border.width: 1
        }
        onAccepted: root.doAdd()
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

    CompletedSection { tasks: root.store ? root.store.recentCompletedTasks : []; store: root.store }
  }
}
