import QtQuick
import Quickshell
import qs.Commons
import qs.Ui
import "Strings.js" as Strings
import "Format.js" as Format

BarWidget {
  id: root
  moduleName: "io.github.agusherrera99.bookflow"

  readonly property string glyph: "󰂺"
  readonly property var book: service.active
  readonly property string label: book ? Format.percent(book.progress_percent) : "—"

  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false
  readonly property bool popoutSwitchClosing: panelLoader.item
    ? panelLoader.item.popoutSwitchClosing === true
    : false

  function open() { if (panelLoader.item) panelLoader.item.open() }
  function close() { if (panelLoader.item) panelLoader.item.close() }
  function toggle() { if (panelLoader.item) panelLoader.item.toggle() }
  function closeForPopoutSwitch() { if (panelLoader.item) panelLoader.item.closeForPopoutSwitch() }

  // Opening the book is a promise that pages are about to move, so drop to the
  // fast poll rather than waiting out the idle interval for the first one.
  function readCurrentBook() {
    service.openBook()
    service.markActive()
  }

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
    if ("service" in target) target.service = service
  }

  function tooltip() {
    if (!service.ready) return Strings.t(service.language, "appName")
    if (!book) return Strings.t(service.language, "noActiveBook")
    var pages = Strings.t(service.language, "progressPages", {
      current: book.furthest_page,
      total: book.total_pages
    })
    return book.title + " · " + pages
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()

  Service {
    id: service
    settings: root.settings
  }

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.vertical ? "" : root.glyph + "  " + root.label
    labelVisible: !root.vertical
    hasVisualContent: true
    tooltipText: root.tooltip()

    onPressed: function(buttonCode) {
      if (buttonCode === Qt.RightButton) root.readCurrentBook()
      else if (buttonCode === Qt.MiddleButton) service.sync()
      else root.toggle()
    }

    OpticalGlyph {
      visible: root.vertical
      anchors.fill: parent
      text: root.glyph
      fontFamily: button.fontFamily
      fontSize: Style.bar.iconFont
      color: button.foreground
    }
  }
}
