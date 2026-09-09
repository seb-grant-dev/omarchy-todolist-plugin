const assert = require("assert")
const Util = require("../Util.js")

function run() {
  // Anchor "today" at a fixed date, but derive week/month boundaries from
  // Util itself rather than hardcoding a weekday, so the test doesn't
  // depend on which day of the week 2026-09-09 happens to be.
  const today = new Date(2026, 8, 9) // 2026-09-09, local midnight

  assert.strictEqual(Util.toISODate(today), "2026-09-09")

  const monday = Util.startOfISOWeek(today)
  const sunday = Util.endOfISOWeek(today)
  const monthEnd = Util.endOfMonth(today)

  assert.ok(monday.getDay() === 1, "startOfISOWeek must land on a Monday")
  assert.ok(sunday.getDay() === 0, "endOfISOWeek must land on a Sunday")
  assert.ok(monday.getTime() <= today.getTime() && today.getTime() <= sunday.getTime(),
    "today must fall within its own ISO week")

  // No due date -> someday
  assert.strictEqual(Util.bucketFor(null, today), "someday")
  assert.strictEqual(Util.bucketFor("", today), "someday")

  // Today and overdue -> today
  assert.strictEqual(Util.bucketFor(Util.toISODate(today), today), "today")
  const yesterday = new Date(today.getFullYear(), today.getMonth(), today.getDate() - 1)
  assert.strictEqual(Util.bucketFor(Util.toISODate(yesterday), today), "today")

  // End of this ISO week (but after today, unless today IS Sunday) -> thisweek,
  // unless sunday === today in which case it's already covered by the
  // "today" case above.
  if (Util.toISODate(sunday) !== Util.toISODate(today)) {
    assert.strictEqual(Util.bucketFor(Util.toISODate(sunday), today), "thisweek")
  }

  // Day after this ISO week, still within this month -> thismonth
  const dayAfterWeek = new Date(sunday.getFullYear(), sunday.getMonth(), sunday.getDate() + 1)
  if (Util.toISODate(dayAfterWeek) <= Util.toISODate(monthEnd)) {
    assert.strictEqual(Util.bucketFor(Util.toISODate(dayAfterWeek), today), "thismonth")
  }

  // Day after month end -> someday
  const dayAfterMonth = new Date(monthEnd.getFullYear(), monthEnd.getMonth(), monthEnd.getDate() + 1)
  assert.strictEqual(Util.bucketFor(Util.toISODate(dayAfterMonth), today), "someday")

  console.log("test-util: all assertions passed")
}

function testRecentCompleted() {
  const now = new Date(2026, 8, 9, 12, 0, 0) // 2026-09-09 noon, local

  const fresh = { id: "a", completedAt: new Date(2026, 8, 9, 9, 0, 0).toISOString() }
  const older = { id: "b", completedAt: new Date(2026, 8, 5, 9, 0, 0).toISOString() }
  const stale = { id: "c", completedAt: new Date(2026, 8, 1, 9, 0, 0).toISOString() } // >7 days before now
  const noTimestamp = { id: "d", completedAt: null }

  // Filters out anything older than the cutoff, and anything with no completedAt
  const result = Util.recentCompleted([fresh, older, stale, noTimestamp], now, 7)
  assert.deepStrictEqual(result.map(function(t) { return t.id }), ["a", "b"])

  // Sorts newest-first
  const unsorted = Util.recentCompleted([older, fresh], now, 7)
  assert.deepStrictEqual(unsorted.map(function(t) { return t.id }), ["a", "b"])

  // Boundary: exactly `days` ago is included
  const exactlyAtCutoff = { id: "e", completedAt: new Date(now.getTime() - 7 * 24 * 60 * 60 * 1000).toISOString() }
  const boundary = Util.recentCompleted([exactlyAtCutoff], now, 7)
  assert.deepStrictEqual(boundary.map(function(t) { return t.id }), ["e"])

  // Empty input -> empty output
  assert.deepStrictEqual(Util.recentCompleted([], now, 7), [])

  console.log("test-util: recentCompleted assertions passed")
}

run()
testRecentCompleted()
