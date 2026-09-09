// Minimal RFC5545 subset: unfolds continuation lines, extracts VEVENT
// blocks, reads DTSTART and SUMMARY, and drops any event containing an
// RRULE line entirely (no recurrence expansion — see design spec
// Non-goals). Not a general-purpose ICS library.

function unfold(raw) {
  var lines = String(raw || "").replace(/\r\n/g, "\n").split("\n")
  var out = []
  for (var i = 0; i < lines.length; i++) {
    if ((lines[i].charAt(0) === " " || lines[i].charAt(0) === "\t") && out.length > 0) {
      out[out.length - 1] += lines[i].slice(1)
    } else {
      out.push(lines[i])
    }
  }
  return out
}

function parseDtstartValue(line) {
  // e.g. "DTSTART:20260910T090000Z" or "DTSTART;VALUE=DATE:20260915"
  var colonIndex = line.indexOf(":")
  if (colonIndex === -1) return null
  var value = line.slice(colonIndex + 1).trim()
  var match = value.match(/^(\d{4})(\d{2})(\d{2})/)
  if (!match) return null
  return match[1] + "-" + match[2] + "-" + match[3]
}

function parse(rawIcsText) {
  var lines = unfold(rawIcsText)
  var events = []
  var current = null

  for (var i = 0; i < lines.length; i++) {
    var line = lines[i]
    if (line.indexOf("BEGIN:VEVENT") === 0) {
      current = { date: null, summary: null, recurring: false }
    } else if (line.indexOf("END:VEVENT") === 0) {
      if (current && current.date && current.summary && !current.recurring) {
        events.push({ date: current.date, summary: current.summary })
      }
      current = null
    } else if (current) {
      if (line.indexOf("DTSTART") === 0) {
        current.date = parseDtstartValue(line)
      } else if (line.indexOf("SUMMARY") === 0) {
        var colonIndex = line.indexOf(":")
        current.summary = colonIndex === -1 ? "" : line.slice(colonIndex + 1).trim()
      } else if (line.indexOf("RRULE") === 0) {
        current.recurring = true
      }
    }
  }

  return events
}

if (typeof module !== "undefined") {
  module.exports = { parse: parse }
}
