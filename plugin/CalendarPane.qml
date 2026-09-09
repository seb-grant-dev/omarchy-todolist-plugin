import QtQuick
import QtQml.Models
import Quickshell.Io
import qs.Commons
import "Util.js" as DateUtil
import "IcsParser.js" as IcsParser

// Note: qs.Commons registers its own singleton also named "Util"
// (Commons/Util.qml, per its qmldir) — importing it as a bare "Util"
// alias here would collide, so this file's own Util.js (date bucketing)
// is aliased "DateUtil" instead. Files that don't import qs.Commons
// (TodoStore.qml) keep the plain "Util" alias.

Item {
  id: root

  property var icsFiles: []
  property var eventsByDate: ({})
  property var _eventsBySource: ({})

  property var viewMonth: new Date().getMonth()
  property var viewYear: new Date().getFullYear()
  property string selectedDate: DateUtil.toISODate(new Date())

  implicitHeight: column.implicitHeight

  function mergeIcsEvents(sourcePath, events) {
    var bySource = {}
    for (var k in root._eventsBySource) bySource[k] = root._eventsBySource[k]
    bySource[sourcePath] = events
    root._eventsBySource = bySource

    var merged = {}
    for (var src in bySource) {
      var list = bySource[src]
      for (var i = 0; i < list.length; i++) {
        var date = list[i].date
        if (!merged[date]) merged[date] = []
        merged[date].push(list[i].summary)
      }
    }
    root.eventsByDate = merged
  }

  Instantiator {
    model: root.icsFiles
    delegate: FileView {
      id: icsFile
      required property string modelData
      path: modelData
      watchChanges: true
      printErrors: false
      onLoaded: root.mergeIcsEvents(modelData, IcsParser.parse(text()))
      onLoadFailed: root.mergeIcsEvents(modelData, [])
    }
  }

  function daysInGrid() {
    var firstOfMonth = new Date(root.viewYear, root.viewMonth, 1)
    var gridStart = DateUtil.startOfISOWeek(firstOfMonth)
    var days = []
    for (var i = 0; i < 42; i++) {
      days.push(new Date(gridStart.getFullYear(), gridStart.getMonth(), gridStart.getDate() + i))
    }
    return days
  }

  Column {
    id: column
    width: parent.width
    spacing: Style.space(8)

    Row {
      width: parent.width
      spacing: Style.space(8)

      Text {
        text: "‹"
        color: Color.foreground
        MouseArea {
          anchors.fill: parent
          onClicked: {
            var d = new Date(root.viewYear, root.viewMonth - 1, 1)
            root.viewYear = d.getFullYear()
            root.viewMonth = d.getMonth()
          }
        }
      }

      Text {
        width: parent.width - Style.space(48)
        horizontalAlignment: Text.AlignHCenter
        text: Qt.formatDate(new Date(root.viewYear, root.viewMonth, 1), "MMMM yyyy")
        color: Color.foreground
        font.pixelSize: Style.font.title
      }

      Text {
        text: "›"
        color: Color.foreground
        MouseArea {
          anchors.fill: parent
          onClicked: {
            var d = new Date(root.viewYear, root.viewMonth + 1, 1)
            root.viewYear = d.getFullYear()
            root.viewMonth = d.getMonth()
          }
        }
      }
    }

    Grid {
      width: parent.width
      columns: 7
      rowSpacing: Style.space(4)
      columnSpacing: Style.space(4)

      Repeater {
        model: root.daysInGrid()
        delegate: Rectangle {
          width: (column.width - Style.space(24)) / 7
          height: width
          radius: Style.cornerRadius
          property string dateStr: DateUtil.toISODate(modelData)
          property bool inMonth: modelData.getMonth() === root.viewMonth
          property bool isToday: dateStr === DateUtil.toISODate(new Date())
          property bool hasEvents: !!root.eventsByDate[dateStr] && root.eventsByDate[dateStr].length > 0
          color: dateStr === root.selectedDate ? Color.accent
            : (isToday ? Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.25) : "transparent")

          Text {
            anchors.centerIn: parent
            text: String(modelData.getDate())
            color: inMonth ? Color.foreground : Color.muted
            font.pixelSize: Style.font.bodySmall
          }

          Rectangle {
            visible: hasEvents
            width: Style.space(4)
            height: Style.space(4)
            radius: Style.space(2)
            color: Color.urgent
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: Style.space(2)
          }

          MouseArea {
            anchors.fill: parent
            onClicked: root.selectedDate = dateStr
          }
        }
      }
    }

    Column {
      width: parent.width
      spacing: Style.space(2)
      visible: (root.eventsByDate[root.selectedDate] || []).length > 0

      Text {
        text: root.selectedDate
        color: Color.muted
        font.pixelSize: Style.font.caption
      }

      Repeater {
        model: root.eventsByDate[root.selectedDate] || []
        delegate: Text {
          width: column.width
          text: "• " + modelData
          color: Color.foreground
          font.pixelSize: Style.font.bodySmall
          wrapMode: Text.Wrap
        }
      }
    }
  }
}
