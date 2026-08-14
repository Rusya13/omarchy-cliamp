import QtQuick
import QtQuick.Controls as QQC
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import qs.Ui
import qs.Commons

BarWidget {
  id: root
  moduleName: "rus.cliamp"

  property bool connected: false
  property string state: ""
  property string eqPreset: "Electronic"
  property string track: ""
  property string trackPath: ""
  property real volumeDb: -30
  property int stationIndex: -1
  property string statusOutput: ""
  property string queueOutput: ""
  property string playOutput: ""
  property var stations: []
  property var bands: []
  property bool popupOpen: false

  readonly property var mprisPlayers: Mpris.players ? Mpris.players.values : []
  readonly property var cliampPlayer: {
    for (var i = 0; i < mprisPlayers.length; i++) {
      var player = mprisPlayers[i]
      if (player && (player.dbusName === "cliamp"
          || player.identity === "Cliamp"
          || player.desktopEntry === "cliamp")) return player
    }
    return null
  }
  readonly property bool playing: state.toLowerCase() === "playing"
  readonly property string playIcon: playing ? "󰏤" : "󰐊"
  readonly property string pauseIcon: "󰏤"
  readonly property string nowPlayingTitle: {
    var title = cliampPlayer && cliampPlayer.trackTitle ? cliampPlayer.trackTitle : track
    return title || "Nothing playing"
  }
  readonly property string currentStation: {
    if (stationIndex >= 0 && stationIndex < stations.length)
      return stations[stationIndex].title || stations[stationIndex].path || ""
    return track
  }
  readonly property string displayTrack: {
    var title = nowPlayingTitle
    return title.length > 30 ? title.substring(0, 29) + "…" : title
  }
  readonly property color themeAccent: Color.accent
  readonly property int maxLabelWidth: Style.space(190)
  readonly property string ipcScriptPath: (Quickshell.env("HOME") || "")
    + "/.config/omarchy/plugins/rus.cliamp/cliamp-ipc.py"
  readonly property string focusScriptPath: (Quickshell.env("HOME") || "")
    + "/.config/omarchy/plugins/rus.cliamp/open-cliamp.py"

  function close() { popupOpen = false }

  function openCliamp() {
    popupOpen = false
    Quickshell.execDetached(["/usr/bin/python3", focusScriptPath])
  }

  function syncStationIndex() {
    if (!stations || stations.length === 0) return
    for (var i = 0; i < stations.length; i++) {
      var item = stations[i]
      if ((trackPath && item.path === trackPath)
          || (!trackPath && item.title === track)) {
        stationIndex = i
        return
      }
    }
  }

  function parseBands(line) {
    try {
      var response = JSON.parse(String(line || "{}"))
      if (response && response.ok && response.bands) bands = response.bands
    } catch (error) {}
  }

  onPopupOpenChanged: if (popupOpen) root.refresh()

  visible: connected
  // Reserve the full visual width so the widget cannot overlap neighboring
  // bar modules (the transparent WidgetButton itself is icon-only).
  implicitWidth: connected ? barContent.implicitWidth + Style.space(14) : 0
  implicitHeight: connected ? barSize : 0

  function applyStatus(output, exitCode) {
    if (exitCode !== 0) {
      connected = false
      return
    }

    var status
    try {
      status = JSON.parse(String(output || "{}"))
    } catch (error) {
      connected = false
      return
    }
    if (!status.ok) {
      connected = false
      return
    }

    state = status.state || ""
    eqPreset = status.eq_preset || eqPreset
    track = status.track && status.track.title ? status.track.title : ""
    trackPath = status.track && status.track.path ? status.track.path : ""
    // Some cliamp versions omit `index` when the current item is index 0.
    // Keep the queue's index instead of clearing the active-station marker.
    if (status.index !== undefined && status.index !== null)
      stationIndex = Number(status.index)
    if (status.volume !== undefined) volumeDb = Math.max(-30, Math.min(6, Number(status.volume)))
    syncStationIndex()
    connected = true
  }

  function applyQueue(output, exitCode) {
    if (exitCode !== 0) return
    var queue
    try {
      queue = JSON.parse(String(output || "{}"))
    } catch (error) {
      return
    }
    if (!queue.ok || !queue.tracks) return
    stations = queue.tracks
    if (queue.index !== undefined) stationIndex = Number(queue.index)
    syncStationIndex()
  }

  function refresh() {
    if (!statusProc.running) {
      statusOutput = ""
      statusProc.running = true
    }
    if (!queueProc.running) {
      queueOutput = ""
      queueProc.running = true
    }
  }

  function runCliamp(args) {
    Quickshell.execDetached(["cliamp"].concat(args))
    refreshTimer.restart()
  }

  function playStation(index) {
    if (index < 0 || index >= stations.length || playProc.running) return
    stationIndex = index
    playProc.command = ["/usr/bin/python3", ipcScriptPath, "play", String(index)]
    playProc.running = true
    refreshTimer.restart()
  }

  function applyPlayedStation(output, exitCode) {
    if (exitCode !== 0) return
    var response
    try { response = JSON.parse(String(output || "{}")) } catch (error) { return }
    if (response.ok && response.index !== undefined) stationIndex = Number(response.index)
    refreshTimer.restart()
  }

  function playRelativeStation(delta) {
    if (stations.length > 0) {
      var index = stationIndex >= 0 ? stationIndex : 0
      index = (index + delta + stations.length) % stations.length
      playStation(index)
    } else {
      runCliamp([delta < 0 ? "prev" : "next"])
    }
  }

  function cycleSoundMode() {
    var modes = ["Flat", "Rock", "Pop", "Jazz", "Classical", "Bass Boost",
      "Treble Boost", "Vocal", "Electronic", "Acoustic"]
    var current = modes.indexOf(eqPreset)
    var next = modes[(current < 0 ? 0 : current + 1) % modes.length]
    eqPreset = next
    runCliamp(["eq", next])
  }

  function setVolume(value) {
    var db = Math.max(-30, Math.min(6, Math.round(value)))
    volumeDb = db
    runCliamp(["volume", String(db)])
  }

  Timer {
    id: refreshTimer
    interval: 500
    repeat: false
    onTriggered: root.refresh()
  }

  Timer {
    interval: 1500
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  Process {
    id: statusProc
    command: ["cliamp", "status", "--json"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.statusOutput = text
    }
    onExited: function(exitCode) { root.applyStatus(root.statusOutput, exitCode) }
  }

  Process {
    id: queueProc
    command: ["/usr/bin/python3", root.ipcScriptPath, "queue"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.queueOutput = text
    }
    onExited: function(exitCode) { root.applyQueue(root.queueOutput, exitCode) }
  }

  Process {
    id: bandsProc
    command: ["cliamp", "visstream", "--fps", "20"]
    running: false
    stdout: SplitParser {
      splitMarker: "\n"
      onRead: function(line) { root.parseBands(line) }
    }
    onExited: bandsRestart.restart()
  }

  Timer {
    id: bandsRestart
    interval: 1500
    running: root.connected && !bandsProc.running
    repeat: true
    onTriggered: bandsProc.running = true
  }

  onConnectedChanged: bandsProc.running = connected

  Process {
    id: playProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.playOutput = text
    }
    stderr: StdioCollector { waitForEnd: true }
    onExited: function(exitCode) { root.applyPlayedStation(root.playOutput, exitCode) }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    labelVisible: false
    hasVisualContent: true
    foreground: root.playing ? root.themeAccent : (root.bar ? root.bar.foreground : Color.foreground)
    fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
    fontSize: Style.font.body
    tooltipText: root.nowPlayingTitle
    useActiveColor: false
    onPressed: function(mouseButton) {
      if (mouseButton === Qt.RightButton) root.popupOpen = !root.popupOpen
      else if (mouseButton === Qt.MiddleButton) root.playRelativeStation(1)
      else root.runCliamp(["toggle"])
    }
    onWheelMoved: function(delta) {
      if (delta > 0) root.playRelativeStation(-1)
      else if (delta < 0) root.playRelativeStation(1)
    }
  }

  Row {
    id: barContent
    anchors.centerIn: button
    spacing: Style.space(6)
    enabled: false

    Item {
      id: equalizer
      width: Style.space(16)
      height: Math.max(Style.space(10), labelText.implicitHeight * 0.7)
      anchors.verticalCenter: parent.verticalCenter

      Text {
        visible: !root.playing
        anchors.centerIn: parent
        text: root.pauseIcon
        color: root.themeAccent
        font.family: root.bar ? root.bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.body
      }

      Row {
        visible: root.playing
        anchors.bottom: parent.bottom
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: Style.space(1)

        Repeater {
          model: 5
          Item {
            required property int index
            width: Style.space(2)
            height: equalizer.height

            Rectangle {
              anchors.bottom: parent.bottom
              width: parent.width
              height: Math.max(Style.space(2), Math.min(parent.height,
                Style.space(2) + (root.bands.length > index ? root.bands[index] : 0) * Style.space(9)))
              color: root.themeAccent
              Behavior on height { NumberAnimation { duration: 90; easing.type: Easing.OutCubic } }
            }
          }
        }
      }
    }

    Item {
      id: labelClip
      width: Math.min(root.maxLabelWidth, labelText.implicitWidth)
      height: labelText.implicitHeight
      clip: true

      Text {
        id: labelText
        text: root.displayTrack
        color: root.bar ? root.bar.foreground : Color.foreground
        font.family: root.bar ? root.bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.body
        elide: Text.ElideRight
        width: labelClip.width
        anchors.verticalCenter: parent.verticalCenter
      }
    }
  }

  PopupCard {
    id: popup
    anchorItem: button
    bar: root.bar
    owner: root
    open: root.popupOpen
    contentWidth: popup.fittedContentWidth(Style.space(340))
    contentHeight: popup.fittedContentHeight(column.implicitHeight)

    Column {
      id: column
      anchors.fill: parent
      spacing: Style.space(8)

      Text {
        text: root.nowPlayingTitle
        color: root.themeAccent
        font.family: root.bar.fontFamily
        font.pixelSize: Style.font.subtitle
        font.bold: true
        elide: Text.ElideRight
        width: parent.width
      }

      Text {
        text: root.currentStation
        color: root.bar.foreground
        font.family: root.bar.fontFamily
        font.pixelSize: Style.font.caption
        elide: Text.ElideRight
        width: parent.width
        visible: text !== ""
      }

      Row {
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: Style.space(6)

        Button {
          iconText: "󰒮"
          tooltipText: "Previous station"
          foreground: root.bar.foreground
          onClicked: root.playRelativeStation(-1)
        }

        Button {
          iconText: root.playIcon
          tooltipText: root.playing ? "Pause" : "Play"
          foreground: root.bar.foreground
          iconSize: Style.font.iconLarge
          onClicked: root.runCliamp(["toggle"])
        }

        Button {
          iconText: "󰒭"
          tooltipText: "Next station"
          foreground: root.bar.foreground
          onClicked: root.playRelativeStation(1)
        }

        Button {
          text: "EQ " + root.eqPreset
          tooltipText: "Next sound mode"
          foreground: root.themeAccent
          onClicked: root.cycleSoundMode()
        }

        Button {
          text: "Open in Pi"
          tooltipText: "Open cliamp in the Pi/Herdr window"
          foreground: root.themeAccent
          onClicked: root.openCliamp()
        }
      }

      PanelSeparator { foreground: root.bar.foreground }

      Text {
        text: "STATIONS"
        color: root.themeAccent
        font.family: root.bar.fontFamily
        font.pixelSize: Style.font.caption
        font.bold: true
        font.letterSpacing: 1.2
      }

      QQC.ScrollView {
        id: stationScroll
        width: parent.width
        height: Style.space(230)
        clip: true
        QQC.ScrollBar.horizontal: QQC.ScrollBar {
          policy: QQC.ScrollBar.AlwaysOff
        }
        QQC.ScrollBar.vertical: QQC.ScrollBar {
          policy: stationList.implicitHeight > stationScroll.height
            ? QQC.ScrollBar.AsNeeded : QQC.ScrollBar.AlwaysOff
        }

        Column {
          id: stationList
          width: stationScroll.availableWidth
          spacing: Style.space(2)

          Repeater {
            model: root.stations

            Button {
              required property var modelData
              required property int index
              width: stationList.width
              text: modelData.title || modelData.path || "Station " + (index + 1)
              iconText: stationActive ? "▸" : ""
              property bool stationActive: index === root.stationIndex
              foreground: stationActive ? root.themeAccent : root.bar.foreground
              accent: root.themeAccent
              horizontalPadding: 0
              leftAlign: true
              selected: stationActive
              tooltipText: modelData.path || ""
              onClicked: root.playStation(index)
            }
          }
        }
      }

      PanelSeparator { foreground: root.bar.foreground }

      Row {
        width: parent.width
        spacing: Style.space(8)

        Text {
          id: volumeLabel
          text: "VOL " + Math.round(root.volumeDb) + " dB"
          color: root.bar.foreground
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.caption
          font.bold: true
          anchors.verticalCenter: parent.verticalCenter
        }

        PanelSlider {
          bar: root.bar
          width: parent.width - volumeLabel.width - Style.space(8)
          minimum: -30
          maximum: 6
          step: 1
          value: root.volumeDb
          onMoved: function(value) { root.setVolume(value) }
        }
      }
    }
  }
}
