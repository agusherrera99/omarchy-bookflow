import QtQuick
import Quickshell
import Quickshell.Io

Item {
  id: root

  property var settings: ({})

  readonly property string cli: Qt.resolvedUrl("bin/bookflow").toString().replace(/^file:\/\//, "")
  readonly property int commandTimeoutSec: 20
  readonly property int activeIntervalSec: 15
  readonly property int activeWindowMs: 300000

  property var status: null
  property var books: []
  property var readers: []
  property bool ready: false
  property bool busy: false
  property bool recentlyActive: false
  property string lastError: ""
  property string lastSyncReason: ""

  // Watching the finished count rather than a per-sync flag catches both ways a
  // book ends: reaching the last page, and the panel's finish button.
  property int finishedCount: -1
  property string lastFinishedTitle: ""

  signal bookFinished(string title)

  readonly property var active: status && status.active ? status.active : null
  readonly property var metrics: status && status.metrics ? status.metrics : ({})
  readonly property var preferences: status && status.preferences ? status.preferences : ({})
  readonly property var reader: status && status.reader ? status.reader : ({})
  readonly property var queue: status && status.queue ? status.queue : []
  readonly property var library: status && status.library ? status.library : ({})

  readonly property string language: preferences.language || "en"
  readonly property real progressPercent: active ? Number(active.progress_percent) : 0
  readonly property bool canCapture: reader.captures === true && reader.available === true

  function setting(name, fallback) {
    var value = settings ? settings[name] : undefined
    return value === undefined || value === null ? fallback : value
  }

  function intSetting(name, fallback, min, max) {
    var number = parseInt(String(setting(name, fallback)), 10)
    if (!isFinite(number)) number = fallback
    return Math.max(min, Math.min(max, number))
  }

  readonly property int idleIntervalSec: intSetting("refreshIntervalSec", 60, 15, 3600)

  function command(args) {
    return ["timeout", "-k", "2", String(commandTimeoutSec), cli].concat(args)
  }

  function refresh() {
    if (statusProcess.running) return
    statusProcess.command = command(["status", "--json"])
    statusProcess.running = true
  }

  function sync() {
    if (statusProcess.running) return
    statusProcess.command = command(["sync", "--json"])
    statusProcess.running = true
  }

  function loadBooks() {
    if (booksProcess.running) return
    booksProcess.command = command(["books", "--json"])
    booksProcess.running = true
  }

  function loadReaders() {
    if (readersProcess.running) return
    readersProcess.command = command(["readers", "--json"])
    readersProcess.running = true
  }

  function act(args, reloadLibrary) {
    if (actionProcess.running) return
    actionProcess.reloadLibrary = reloadLibrary === true
    actionProcess.command = command(args)
    root.busy = true
    actionProcess.running = true
  }

  function selectBook(bookId) { act(["select", String(bookId), "--json"], true) }
  function openBook() { act(["open", "--json"], false) }
  function finishBook() { act(["finish", "--json"], true) }
  function pauseBook() { act(["pause", "--json"], true) }
  function setPage(page) { act(["set-page", String(page), "--json"], false) }
  function rescan() { act(["scan", "--json"], true) }
  function setPreference(key, value) { act(["prefs", "--set", key + "=" + value, "--json"], false) }

  function markActive() {
    recentlyActive = true
    activeWindow.restart()
  }

  function parsePayload(text) {
    var raw = String(text || "").trim()
    if (raw === "") return null
    try {
      return JSON.parse(raw)
    } catch (error) {
      root.lastError = String(error)
      return null
    }
  }

  Component.onCompleted: {
    loadReaders()
    loadBooks()
  }

  Timer {
    id: pollTimer
    interval: (root.recentlyActive ? root.activeIntervalSec : root.idleIntervalSec) * 1000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.sync()
  }

  Timer {
    id: activeWindow
    interval: root.activeWindowMs
    onTriggered: root.recentlyActive = false
  }

  Process {
    id: statusProcess
    running: false
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var payload = root.parsePayload(text)
        if (!payload) return

        var finishing = root.active && payload.library
          && Number(payload.library.done) > root.finishedCount
          && root.finishedCount >= 0
          ? String(root.active.title || "")
          : ""

        root.status = payload
        root.ready = true
        root.lastError = ""
        if (payload.library && payload.library.done !== undefined)
          root.finishedCount = Number(payload.library.done)
        if (payload.sync) {
          root.lastSyncReason = String(payload.sync.reason || "")
          if (payload.sync.changed === true) root.markActive()
        }

        // Emitted after the payload lands so anything reacting to it reads the
        // state the finish produced, not the one before it.
        if (finishing !== "") {
          root.lastFinishedTitle = finishing
          root.bookFinished(finishing)
        }
      }
    }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var message = String(text || "").trim()
        if (message !== "") root.lastError = message
      }
    }
  }

  Process {
    id: booksProcess
    running: false
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var payload = root.parsePayload(text)
        if (payload && payload.books) root.books = payload.books
      }
    }
  }

  Process {
    id: readersProcess
    running: false
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var payload = root.parsePayload(text)
        if (payload && payload.readers) root.readers = payload.readers
      }
    }
  }

  Process {
    id: actionProcess
    property bool reloadLibrary: false
    running: false
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var message = String(text || "").trim()
        if (message !== "") root.lastError = message
      }
    }
    onExited: {
      root.busy = false
      root.refresh()
      if (reloadLibrary) root.loadBooks()
    }
  }
}
