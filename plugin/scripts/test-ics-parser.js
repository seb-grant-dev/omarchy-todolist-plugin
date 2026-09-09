const assert = require("assert")
const IcsParser = require("../IcsParser.js")

const fixture = [
  "BEGIN:VCALENDAR",
  "VERSION:2.0",
  "BEGIN:VEVENT",
  "UID:1@example.com",
  "DTSTART:20260910T090000Z",
  "SUMMARY:Dentist",
  "END:VEVENT",
  "BEGIN:VEVENT",
  "UID:2@example.com",
  "DTSTART;VALUE=DATE:20260915",
  "SUMMARY:Project deadline",
  "END:VEVENT",
  "BEGIN:VEVENT",
  "UID:3@example.com",
  "DTSTART:20260901T090000Z",
  "RRULE:FREQ=WEEKLY;BYDAY=TU",
  "SUMMARY:Weekly standup",
  "END:VEVENT",
  "BEGIN:VEVENT",
  "UID:4@example.com",
  "SUMMARY:Missing DTSTART, should be skipped",
  "END:VEVENT",
  "END:VCALENDAR"
].join("\r\n")

function run() {
  const events = IcsParser.parse(fixture)

  assert.strictEqual(events.length, 2, "recurring and malformed events must be excluded")

  const dentist = events.find(function(e) { return e.summary === "Dentist" })
  assert.ok(dentist, "non-recurring timed event must be included")
  assert.strictEqual(dentist.date, "2026-09-10")

  const deadline = events.find(function(e) { return e.summary === "Project deadline" })
  assert.ok(deadline, "non-recurring all-day (VALUE=DATE) event must be included")
  assert.strictEqual(deadline.date, "2026-09-15")

  assert.ok(!events.find(function(e) { return e.summary === "Weekly standup" }),
    "event with RRULE must be excluded entirely")
  assert.ok(!events.find(function(e) { return e.summary && e.summary.indexOf("Missing DTSTART") !== -1 }),
    "event without DTSTART must be excluded")

  console.log("test-ics-parser: all assertions passed")
}

run()
