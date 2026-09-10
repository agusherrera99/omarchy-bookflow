import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Ui
import "Strings.js" as Strings
import "Format.js" as Format

Panel {
  id: root
  moduleName: "io.github.agusherrera99.bookflow"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  property var service: null
  property bool settingsOpen: false

  readonly property var barIdentity: hostWidget || root
  readonly property string language: service ? service.language : "en"
  readonly property var book: service ? service.active : null
  readonly property var metrics: service ? service.metrics : ({})
  readonly property var preferences: service ? service.preferences : ({})
  readonly property var reader: service ? service.reader : ({})
  readonly property var library: service ? service.library : ({})

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property color accent: Color.accent
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  readonly property bool currentBookFinished: book !== null && book.status === "done"
  readonly property real percent: book ? Number(book.progress_percent) : 0
  readonly property string unitLabel: book && book.unit_type === "estimated_page"
    ? t("unitEstimatedPage")
    : t("unitPage")

  function t(key, fields) { return Strings.t(language, key, fields) }
  function tn(count, key, fields) { return Strings.tn(language, count, key, fields) }

  function statusHint() {
    if (!service || !service.ready) return ""
    if (!book) return t("noActiveHint")
    if (currentBookFinished) return t("finishedNote")
    if (reader.available === false) return t("readerMissing", { reader: reader.label || reader.id })
    if (reader.captures === false) return t("manualHint", { reader: reader.label || reader.id })
    if (service.lastSyncReason === "no-saved-position") return t("waitingForPage")
    return ""
  }

  function bookOptions() {
    var options = []
    var entries = service ? service.books : []
    for (var index = 0; index < entries.length; index++) {
      var entry = entries[index]
      options.push({
        value: String(entry.id),
        label: entry.title,
        description: Format.collectionLabel(entry.collection)
          + " · " + Format.percent(entry.progress_percent)
      })
    }
    return options
  }

  function readerOptions() {
    var options = []
    var entries = service ? service.readers : []
    for (var index = 0; index < entries.length; index++) {
      options.push({ value: entries[index].id, label: entries[index].label })
    }
    return options
  }

  function scrollBy(amount) {
    if (!flick.interactive) return
    var limit = Math.max(0, flick.contentHeight - flick.height)
    flick.contentY = Math.max(0, Math.min(limit, flick.contentY + amount))
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(400))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(980))

    onOpenChanged: if (open && root.service) root.service.sync()

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent

      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onMoveRequested: function(dx, dy) { root.scrollBy(dy * Style.space(48)) }
      onTextKey: function(key) {
        if (!root.service) return
        var lowered = String(key).toLowerCase()
        if (lowered === "o") root.service.openBook()
        else if (lowered === "s") root.service.sync()
        else if (lowered === "f") root.service.finishBook()
        else if (lowered === "p") root.service.pauseBook()
        // "," is the conventional preferences key, but it is invisible as a
        // hint badge, so "c" is what the panel advertises. Both work.
        else if (lowered === "r" && root.currentBookFinished) root.service.restartBook()
        else if (lowered === "c" || lowered === ",") root.settingsOpen = !root.settingsOpen
      }

      Flickable {
        id: flick
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: column
          width: flick.width
          spacing: Style.space(12)

          PanelHero {
            width: parent.width
            title: root.book ? root.book.title : root.t("noActiveBook")
            meta: root.book
              ? Format.collectionLabel(root.book.collection)
              : root.t("appName")
            detail: root.book ? root.t("percentOf", { percent: Format.decimal(root.percent) }) : ""
            foreground: root.foreground
            fontFamily: root.fontFamily
            iconComponent: Component {
              Text {
                textFormat: Text.PlainText
                text: "󰂺"
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.display
              }
            }
          }

          Column {
            visible: root.book !== null
            width: parent.width
            spacing: Style.spacing.labelGap

            Item {
              width: parent.width
              height: Style.space(6)

              Rectangle {
                anchors.fill: parent
                radius: height / 2
                color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.15)
              }

              Rectangle {
                height: parent.height
                width: parent.width * Math.max(0, Math.min(1, root.percent / 100))
                radius: height / 2
                color: root.accent
                Behavior on width { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
              }
            }

            RowLayout {
              width: parent.width
              spacing: Style.space(8)

              Text {
                textFormat: Text.PlainText
                Layout.fillWidth: true
                text: root.book
                  ? root.t("progressPages", {
                      current: root.book.furthest_page,
                      total: root.book.total_pages
                    }) + " " + root.unitLabel
                  : ""
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                elide: Text.ElideRight
              }

              Text {
                textFormat: Text.PlainText
                text: root.book
                  ? root.tn(root.book.remaining_pages, "pagesLeft", { count: root.book.remaining_pages })
                  : ""
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
              }
            }
          }

          Text {
            textFormat: Text.PlainText
            visible: text !== ""
            width: parent.width
            text: root.statusHint()
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }

          Text {
            textFormat: Text.PlainText
            visible: root.service !== null && root.service.lastError !== ""
            width: parent.width
            text: root.service ? root.service.lastError : ""
            color: bar ? bar.urgent : Color.urgent
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }

          PanelSeparator {
            visible: root.book !== null
            foreground: root.foreground
          }

          Column {
            // A finished book has nothing left to estimate; the zeroes would
            // read as a broken calculation rather than an absent one.
            visible: root.book !== null && !root.currentBookFinished
            width: parent.width
            spacing: Style.space(10)

            PanelSectionHeader {
              text: root.t("estimateHeader")
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            RowLayout {
              width: parent.width
              spacing: Style.space(8)

              MetricTile {
                Layout.fillWidth: true
                value: Format.count(root.metrics.sessions_remaining)
                caption: root.tn(root.metrics.sessions_remaining, "metricSessions")
              }

              MetricTile {
                Layout.fillWidth: true
                value: Format.count(root.metrics.days_remaining)
                caption: root.tn(root.metrics.days_remaining, "metricDays")
              }

              MetricTile {
                Layout.fillWidth: true
                value: Format.shortDate(root.language, root.metrics.eta_date)
                caption: root.t("metricFinish")
              }
            }

            InfoRow {
              label: root.t("pace")
              value: root.t("paceValue", { value: Format.decimal(root.metrics.pace_pages_per_session) })
              note: root.metrics.pace_source === "history"
                ? root.t("sourceHistory")
                : root.t("sourceConfigured")
            }

            InfoRow {
              label: root.t("rhythm")
              value: root.t("rhythmValue", { value: Format.decimal(root.metrics.sessions_per_week) })
              note: root.metrics.sessions_per_week_source === "history"
                ? root.t("sourceHistory")
                : root.t("sourceConfigured")
            }

            InfoRow {
              label: root.t("confidence")
              value: root.t("confidence" + String(root.metrics.confidence || "none")
                .replace(/^./, function(first) { return first.toUpperCase() }))
            }

            InfoRow {
              label: root.t("today")
              value: root.tn(root.metrics.pages_today, "pagesCount",
                { count: Format.count(root.metrics.pages_today) })
              note: root.t("lastWeek") + ": "
                + root.tn(root.metrics.pages_last_7_days, "pagesCount",
                    { count: Format.count(root.metrics.pages_last_7_days) })
            }
          }

          Button {
            visible: root.currentBookFinished
            width: parent.width
            text: root.t("readAgain")
            bordered: true
            enabled: !(root.service && root.service.busy)
            onClicked: if (root.service) root.service.restartBook()
          }

          RowLayout {
            visible: !root.currentBookFinished
            width: parent.width
            spacing: Style.space(8)

            ActionKey {
              glyph: "󰂽"
              hint: "o"
              tooltip: root.t("openBook")
              actionEnabled: root.book !== null && !(root.service && root.service.busy)
              onTriggered: if (root.service) root.service.openBook()
            }

            ActionKey {
              glyph: "󰑐"
              hint: "s"
              tooltip: root.t("syncNow")
              actionEnabled: root.book !== null
              onTriggered: if (root.service) root.service.sync()
            }

            Item { Layout.fillWidth: true; implicitHeight: 1 }

            ActionKey {
              glyph: "󰏤"
              hint: "p"
              tooltip: root.t("pauseBook")
              actionEnabled: root.book !== null && !(root.service && root.service.busy)
              onTriggered: if (root.service) root.service.pauseBook()
            }

            ActionKey {
              glyph: "󰄬"
              hint: "f"
              tooltip: root.t("finishBook")
              actionEnabled: root.book !== null && !(root.service && root.service.busy)
              onTriggered: if (root.service) root.service.finishBook()
            }
          }

          PanelSeparator { foreground: root.foreground }

          Column {
            width: parent.width
            spacing: Style.space(8)

            PanelSectionHeader {
              text: root.t("libraryHeader")
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            SearchableDropdown {
              width: parent.width
              label: root.t("changeBook")
              placeholderText: root.t("searchPlaceholder")
              emptyText: root.t("noMatches")
              triggerLabel: root.book ? root.book.title : root.t("noActiveBook")
              value: root.book ? String(root.book.id) : ""
              options: root.bookOptions()
              fontFamily: root.fontFamily
              onChanged: function(value) {
                if (root.service && value !== "") root.service.selectBook(parseInt(value, 10))
              }
            }

            Text {
              textFormat: Text.PlainText
              width: parent.width
              text: root.t("librarySummary", {
                done: Format.count(root.library.done),
                total: Format.count(root.library.total)
              })
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
          }

          PanelSeparator { foreground: root.foreground }

          Item {
            width: parent.width
            implicitHeight: settingsHeader.implicitHeight + Style.space(6)

            PanelSectionHeader {
              id: settingsHeader
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              text: root.t("settingsHeader")
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Row {
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(5)

              Text {
                anchors.verticalCenter: parent.verticalCenter
                textFormat: Text.PlainText
                text: "c"
                color: root.foreground
                opacity: 0.3
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }

              Text {
                anchors.verticalCenter: parent.verticalCenter
                textFormat: Text.PlainText
                text: root.settingsOpen ? "󰅃" : "󰅀"
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.icon
              }
            }

            MouseArea {
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.settingsOpen = !root.settingsOpen
            }
          }

          Column {
            visible: root.settingsOpen
            width: parent.width
            spacing: Style.space(10)

            Dropdown {
              width: parent.width
              label: root.t("languageLabel")
              value: root.language
              options: Strings.LANGUAGE_OPTIONS
              fontFamily: root.fontFamily
              onChanged: function(value) {
                if (root.service) root.service.setPreference("language", value)
              }
            }

            Dropdown {
              width: parent.width
              label: root.t("readerLabel")
              value: root.preferences.reader || ""
              options: root.readerOptions()
              fontFamily: root.fontFamily
              onChanged: function(value) {
                if (root.service) root.service.setPreference("reader", value)
              }
            }

            NumberField {
              width: parent.width
              label: root.t("setPage")
              value: root.book ? Number(root.book.current_page) : 0
              from: 0
              to: root.book ? Math.max(1, Number(root.book.total_pages)) : 9999
              stepSize: 1
              foreground: root.foreground
              accent: root.accent
              fontFamily: root.fontFamily
              enabled: root.book !== null
              onModified: function(value) {
                if (root.service) root.service.setPage(value)
              }
            }

            NumberField {
              width: parent.width
              label: root.t("pagesPerSessionLabel")
              value: Number(root.preferences.pages_per_session || 10)
              from: 1
              to: 500
              stepSize: 1
              foreground: root.foreground
              accent: root.accent
              fontFamily: root.fontFamily
              onModified: function(value) {
                if (root.service) root.service.setPreference("pages_per_session", value)
              }
            }

            NumberField {
              width: parent.width
              label: root.t("sessionsPerWeekLabel")
              value: Number(root.preferences.sessions_per_week || 5)
              from: 1
              to: 21
              stepSize: 1
              foreground: root.foreground
              accent: root.accent
              fontFamily: root.fontFamily
              onModified: function(value) {
                if (root.service) root.service.setPreference("sessions_per_week", value)
              }
            }

            Column {
              width: parent.width
              spacing: Style.spacing.labelGap

              Text {
                textFormat: Text.PlainText
                text: root.t("catalogLabel")
                color: root.foreground
                opacity: 0.6
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
              }

              TextField {
                id: catalogField
                width: parent.width
                text: root.preferences.catalog_path || ""
                foreground: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                onEditingFinished: {
                  if (root.service && text !== root.preferences.catalog_path)
                    root.service.setPreference("catalog_path", text)
                }
              }
            }

            Button {
              width: parent.width
              text: root.t("rescan")
              iconText: "󰑐"
              bordered: true
              enabled: !(root.service && root.service.busy)
              onClicked: if (root.service) root.service.rescan()
            }
          }
        }
      }
    }
  }

  // An action and the key that fires it. The letter rides in the gap the icon
  // row already had, so discovering the shortcuts costs no layout and no
  // second glance: dim, caption-sized, and subordinate to the icon it labels.
  component ActionKey: Row {
    id: actionKey

    property string glyph: ""
    property string hint: ""
    property string tooltip: ""
    property bool actionEnabled: true

    signal triggered()

    spacing: Style.space(3)

    PanelActionButton {
      anchors.verticalCenter: parent.verticalCenter
      iconText: actionKey.glyph
      tooltipText: actionKey.tooltip + " · " + actionKey.hint
      foreground: root.foreground
      fontFamily: root.fontFamily
      enabled: actionKey.actionEnabled
      onClicked: actionKey.triggered()
    }

    Text {
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.PlainText
      text: actionKey.hint
      color: root.foreground
      opacity: actionKey.actionEnabled ? 0.3 : 0.12
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
    }
  }

  component MetricTile: Column {
    id: tile

    property string value: ""
    property string caption: ""

    spacing: Style.spacing.labelGap

    Text {
      textFormat: Text.PlainText
      width: tile.width
      text: tile.value
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.heading
      elide: Text.ElideRight
    }

    Text {
      textFormat: Text.PlainText
      width: tile.width
      text: tile.caption
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      elide: Text.ElideRight
    }
  }

  component InfoRow: Column {
    id: infoRow

    property string label: ""
    property string value: ""
    property string note: ""

    width: parent.width
    spacing: Style.spacing.labelGap

    RowLayout {
      width: infoRow.width
      spacing: Style.space(8)

      Text {
        textFormat: Text.PlainText
        text: infoRow.label
        color: root.foreground
        opacity: 0.6
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
      }

      Item { Layout.fillWidth: true; implicitHeight: 1 }

      Text {
        textFormat: Text.PlainText
        Layout.maximumWidth: infoRow.width * 0.65
        text: infoRow.value
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        elide: Text.ElideRight
        horizontalAlignment: Text.AlignRight
      }
    }

    Text {
      textFormat: Text.PlainText
      visible: infoRow.note !== ""
      width: infoRow.width
      text: infoRow.note
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      elide: Text.ElideRight
    }
  }
}
