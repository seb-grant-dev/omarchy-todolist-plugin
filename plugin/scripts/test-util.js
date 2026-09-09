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

run()
