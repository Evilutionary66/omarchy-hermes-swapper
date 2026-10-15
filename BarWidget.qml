import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Bar control for the Hermes Agent's model server. Left click cycles to the
// next profile, middle click re-reads the live config. All profile logic lives
// in Model.js so it can be tested without QML; this file only drives the
// `hermes` CLI and renders what it reports.
BarWidget {
  id: root
  moduleName: "hermes-model-swapper"

  // The hermes CLI ships in ~/.local/bin. Override with a "hermesCommand"
  // entry on the widget's shell.json layout line if it lives elsewhere.
  readonly property string cli: String(root.setting("hermesCommand", "hermes"))
  readonly property string notifyPath: (Quickshell.env("OMARCHY_PATH") || "/usr/share/omarchy")
    + "/bin/omarchy-notification-send"
  readonly property int pollInterval: Number(root.setting("refreshInterval", 300000))

  property string profileId: ""
  property string targetId: ""
  property string status: "Reading the Hermes config"
  property bool alert: false
  property bool busy: false
  property bool refreshPending: false
  property var queue: []

  readonly property var profile: Model.profileById(root.profileId)
  readonly property string shortLabel: root.profile ? root.profile.shortLabel : "--"

  function refresh() {
    if (readProc.running) {
      root.refreshPending = true
      return
    }
    readProc.running = true
  }

  function cycle() {
    if (!root.bar || root.busy) return
    var target = Model.nextProfile(root.profileId)
    var steps = Model.setArgs(target)
    if (steps.length === 0) return
    root.targetId = target.id
    root.queue = steps
    root.busy = true
    root.status = "Switching Hermes to " + target.label
    root.nextWrite()
  }

  // One `hermes config set` per call: the CLI takes exactly one key/value pair
  // per invocation, so a profile change is a short queue run one after another.
  function nextWrite() {
    if (!root.queue.length) {
      root.busy = false
      root.queue = []
      root.refresh()
      return
    }
    var args = root.queue.shift()
    writeProc.step = String(args[0] + " " + args[1])
    writeProc.command = [root.cli].concat(args)
    writeProc.running = true
  }

  function readFinished(code, out, err) {
    var parsed = Model.parseModelJson(out)
    var found = Model.detectProfile(parsed)

    if (code !== 0 && !found) {
      root.alert = true
      root.status = "Could not read the Hermes config: "
        + (String(err || "").trim() || "hermes exited with code " + code)
      root.notify("critical", root.status)
      return
    }

    root.profileId = found ? found.id : ""
    root.alert = found === null
    root.status = Model.statusLine(found, parsed)

    if (root.targetId !== "") {
      var wanted = Model.profileById(root.targetId)
      root.targetId = ""
      if (found && wanted && found.id === wanted.id) {
        root.notify("normal", root.status, wanted.glyph)
      } else {
        root.notify("critical", root.status)
      }
    }
  }

  function writeFinished(code, step, out, err) {
    if (code === 124 || code === 137) {
      root.queue = []
      root.busy = false
      root.alert = true
      root.status = "Hermes took too long to answer; try again."
      root.notify("critical", root.status)
      root.refresh()
      return
    }
    if (code !== 0) {
      root.queue = []
      root.busy = false
      root.alert = true
      root.status = "hermes config set " + step + " failed: "
        + (String(err || "").trim() || "exit code " + code)
      root.notify("critical", root.status)
      root.refresh()
      return
    }
    root.nextWrite()
  }

  function notify(urgency, text, glyph) {
    if (!root.bar || notifyProc.running) return
    notifyProc.command = [root.notifyPath, "-g", glyph || "\udb81\udce1", "-u", urgency,
      "Hermes Model Swapper", text]
    notifyProc.running = true
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  IpcHandler {
    target: "hermes-model-swapper"

    function refresh(): void {
      root.broadcast("refresh")
    }

    function swap(): void {
      root.broadcast("cycle")
    }
  }

  Process {
    id: readProc
    command: [root.cli, "config", "get", "model", "--json"]
    onRunningChanged: {
      if (running) {
        readStall.restart()
        return
      }
      readStall.stop()
      if (root.refreshPending) {
        root.refreshPending = false
        Qt.callLater(root.refresh)
      }
    }
    stdout: StdioCollector { id: readOut; waitForEnd: true }
    stderr: StdioCollector { id: readErr; waitForEnd: true }
    onExited: function(code) {
      root.readFinished(code, readOut.text, readErr.text)
    }
  }

  Process {
    id: writeProc
    property string step: ""
    onRunningChanged: {
      if (running) writeStall.restart()
      else writeStall.stop()
    }
    stdout: StdioCollector { id: writeOut; waitForEnd: true }
    stderr: StdioCollector { id: writeErr; waitForEnd: true }
    onExited: function(code) {
      root.writeFinished(code, writeProc.step, writeOut.text, writeErr.text)
    }
  }

  Process {
    id: notifyProc
  }

  // A `hermes` call that never returns would otherwise freeze the widget: a
  // Process that is already running cannot be re-run. Kill the overstaying one
  // so a later refresh can get through. Each Process gets its own timer, so
  // finishing one call cannot cancel the watchdog guarding the other.
  Timer {
    id: readStall
    interval: 5000
    onTriggered: {
      readProc.running = false
      root.alert = true
      root.status = "Hermes did not answer while reading its config."
    }
  }

  Timer {
    id: writeStall
    interval: 5000
    onTriggered: {
      writeProc.running = false
      root.queue = []
      root.busy = false
      root.alert = true
      root.status = "Hermes did not answer while setting " + writeProc.step + "."
    }
  }

  // Nothing here changes on its own, so the only routine read is a slow one.
  Timer {
    interval: root.pollInterval
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "\udb81\udce1"
    slotSize: Style.bar.statusSlot
    fontSize: Style.font.caption
    active: root.alert
    tooltipText: root.status
    onPressed: function(b) {
      if (b === Qt.LeftButton) root.cycle()
      else if (b === Qt.MiddleButton) root.broadcast("refresh")
    }
  }

  // Which server Hermes is currently pointed at.
  Rectangle {
    visible: root.profile !== null
    anchors.top: button.top
    anchors.right: button.right
    z: 10
    implicitWidth: Math.max(Style.space(14), badgeLabel.implicitWidth + Style.space(6))
    implicitHeight: Style.space(14)
    radius: height / 2
    color: root.alert ? Color.urgent : Color.accent
    border.width: 1
    border.color: root.bar ? root.bar.background : "transparent"

    Text {
      id: badgeLabel
      anchors.centerIn: parent
      text: root.shortLabel
      color: "white"
      font.family: root.bar ? root.bar.fontFamily : Style.font.family
      font.pixelSize: Style.font.caption * 0.85
      font.bold: true
    }
  }
}
