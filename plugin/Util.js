function toISODate(date) {
  var y = date.getFullYear()
  var m = String(date.getMonth() + 1).padStart(2, "0")
  var d = String(date.getDate()).padStart(2, "0")
  return y + "-" + m + "-" + d
}

function parseISODate(str) {
  var parts = String(str || "").split("-")
  if (parts.length !== 3) return null
  var y = parseInt(parts[0], 10)
  var m = parseInt(parts[1], 10)
  var d = parseInt(parts[2], 10)
  if (!y || !m || !d) return null
  return new Date(y, m - 1, d)
}

function startOfISOWeek(date) {
  var day = date.getDay() // 0=Sun..6=Sat
  var diffToMonday = day === 0 ? -6 : 1 - day
  return new Date(date.getFullYear(), date.getMonth(), date.getDate() + diffToMonday)
}

function endOfISOWeek(date) {
  var monday = startOfISOWeek(date)
  return new Date(monday.getFullYear(), monday.getMonth(), monday.getDate() + 6)
}

function endOfMonth(date) {
  return new Date(date.getFullYear(), date.getMonth() + 1, 0)
}

function bucketFor(dueDateStr, today) {
  if (!dueDateStr) return "someday"
  var due = parseISODate(dueDateStr)
  if (!due) return "someday"

  var todayISO = toISODate(today)
  var dueISO = toISODate(due)

  if (dueISO <= todayISO) return "today"
  if (dueISO <= toISODate(endOfISOWeek(today))) return "thisweek"
  if (dueISO <= toISODate(endOfMonth(today))) return "thismonth"
  return "someday"
}

function recentCompleted(tasks, now, days) {
  var cutoff = now.getTime() - days * 24 * 60 * 60 * 1000
  return tasks
    .filter(function(t) { return t.completedAt && new Date(t.completedAt).getTime() >= cutoff })
    .sort(function(a, b) { return new Date(b.completedAt).getTime() - new Date(a.completedAt).getTime() })
}

if (typeof module !== "undefined") {
  module.exports = {
    toISODate: toISODate,
    parseISODate: parseISODate,
    startOfISOWeek: startOfISOWeek,
    endOfISOWeek: endOfISOWeek,
    endOfMonth: endOfMonth,
    bucketFor: bucketFor,
    recentCompleted: recentCompleted
  }
}
