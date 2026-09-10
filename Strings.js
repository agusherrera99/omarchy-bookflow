.pragma library

var TABLES = {
  en: {
    appName: "Bookflow",
    noActiveBook: "No book selected",
    noActiveHint: "Pick one from your library to start tracking.",
    openBook: "Open book",
    syncNow: "Sync now",
    finishBook: "Mark as finished",
    pauseBook: "Pause",
    progressPages: "{current} of {total}",
    pagesLeftOne: "{count} left",
    pagesLeftOther: "{count} left",
    unitPage: "pages",
    unitEstimatedPage: "estimated pages",
    metricSessionsOne: "session",
    metricSessionsOther: "sessions",
    metricDaysOne: "day",
    metricDaysOther: "days",
    metricFinish: "finish",
    estimateHeader: "TIME TO FINISH",
    confidence: "Confidence",
    confidenceNone: "not enough data",
    confidenceLow: "low",
    confidenceMedium: "medium",
    confidenceHigh: "high",
    pace: "Pace",
    paceValue: "{value} pages / session",
    sourceHistory: "from your reading history",
    sourceConfigured: "from your settings",
    rhythm: "Rhythm",
    rhythmValue: "{value} sessions / week",
    today: "Read today",
    lastWeek: "Last 7 days",
    pagesCountOne: "{count} page",
    pagesCountOther: "{count} pages",
    libraryHeader: "LIBRARY",
    changeBook: "Change book",
    searchPlaceholder: "Search your library...",
    noMatches: "No matches",
    librarySummary: "{done} of {total} books finished",
    settingsHeader: "SETTINGS",
    settings: "Settings",
    languageLabel: "Language",
    readerLabel: "Reader",
    catalogLabel: "Library folder",
    pagesPerSessionLabel: "Pages per session",
    sessionsPerWeekLabel: "Sessions per week",
    rescan: "Rescan library",
    setPage: "Current page",
    manualHint: "{reader} does not report a page. Set it by hand below.",
    waitingForPage: "Open the book once so the reader saves a position.",
    readerMissing: "{reader} is not installed.",
    fileMissing: "The book file is missing from your library folder.",
    done: "Finished",
    percentOf: "{percent}% read"
  },
  es: {
    appName: "Bookflow",
    noActiveBook: "Sin libro seleccionado",
    noActiveHint: "Elegí uno de tu biblioteca para empezar a seguirlo.",
    openBook: "Abrir libro",
    syncNow: "Sincronizar",
    finishBook: "Marcar como terminado",
    pauseBook: "Pausar",
    progressPages: "{current} de {total}",
    pagesLeftOne: "falta {count}",
    pagesLeftOther: "faltan {count}",
    unitPage: "páginas",
    unitEstimatedPage: "páginas estimadas",
    metricSessionsOne: "sesión",
    metricSessionsOther: "sesiones",
    metricDaysOne: "día",
    metricDaysOther: "días",
    metricFinish: "termina",
    estimateHeader: "CUÁNTO FALTA",
    confidence: "Confianza",
    confidenceNone: "sin datos suficientes",
    confidenceLow: "baja",
    confidenceMedium: "media",
    confidenceHigh: "alta",
    pace: "Ritmo",
    paceValue: "{value} páginas / sesión",
    sourceHistory: "según tu historial de lectura",
    sourceConfigured: "según tu configuración",
    rhythm: "Frecuencia",
    rhythmValue: "{value} sesiones / semana",
    today: "Leído hoy",
    lastWeek: "Últimos 7 días",
    pagesCountOne: "{count} página",
    pagesCountOther: "{count} páginas",
    libraryHeader: "BIBLIOTECA",
    changeBook: "Cambiar libro",
    searchPlaceholder: "Buscá en tu biblioteca...",
    noMatches: "Sin resultados",
    librarySummary: "{done} de {total} libros terminados",
    settingsHeader: "AJUSTES",
    settings: "Ajustes",
    languageLabel: "Idioma",
    readerLabel: "Lector",
    catalogLabel: "Carpeta de la biblioteca",
    pagesPerSessionLabel: "Páginas por sesión",
    sessionsPerWeekLabel: "Sesiones por semana",
    rescan: "Reescanear biblioteca",
    setPage: "Página actual",
    manualHint: "{reader} no informa la página. Fijala a mano acá abajo.",
    waitingForPage: "Abrí el libro una vez para que el lector guarde la posición.",
    readerMissing: "{reader} no está instalado.",
    fileMissing: "Falta el archivo del libro en la carpeta de la biblioteca.",
    done: "Terminado",
    percentOf: "{percent}% leído"
  }
}

var LANGUAGE_OPTIONS = [
  { value: "en", label: "English" },
  { value: "es", label: "Español" }
]

function table(language) {
  return TABLES[language] || TABLES.en
}

function tn(language, count, key, fields) {
  var suffix = Math.abs(Number(count)) === 1 ? "One" : "Other"
  return t(language, key + suffix, fields)
}

function t(language, key, fields) {
  var value = table(language)[key]
  if (value === undefined) value = TABLES.en[key]
  if (value === undefined) return key
  if (!fields) return value
  return value.replace(/\{(\w+)\}/g, function(match, name) {
    return fields[name] === undefined ? match : String(fields[name])
  })
}
