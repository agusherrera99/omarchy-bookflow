.pragma library

var MONTHS = {
  en: ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"],
  es: ["ene", "feb", "mar", "abr", "may", "jun", "jul", "ago", "sep", "oct", "nov", "dic"]
}

function percent(value) {
  var number = Number(value)
  if (!isFinite(number)) return "0%"
  return (number >= 10 ? Math.round(number) : Math.round(number * 10) / 10) + "%"
}

function shortDate(language, isoDate) {
  if (!isoDate) return "—"
  var parts = String(isoDate).split("-")
  if (parts.length < 3) return String(isoDate)
  var months = MONTHS[language] || MONTHS.en
  var month = months[parseInt(parts[1], 10) - 1] || parts[1]
  return parseInt(parts[2], 10) + " " + month
}

function count(value) {
  var number = Number(value)
  return isFinite(number) ? String(Math.round(number)) : "0"
}

function decimal(value) {
  var number = Number(value)
  if (!isFinite(number)) return "0"
  return String(Math.round(number * 10) / 10)
}

function collectionLabel(value) {
  if (!value) return ""
  return String(value).replace(/[_-]+/g, " ")
}
