import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Ui

Panel {
  id: root
  moduleName: "io.github.gustavonline.local-ai-pi-copilot"
  ipcTarget: "io.github.gustavonline.local-ai-pi-copilot"
  manageIpc: false

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property color accent: Color.accent
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property string controlPath: decodeURIComponent(
    String(Qt.resolvedUrl("local-ai-pi-copilot")).replace(/^file:\/\//, "")
  )
  readonly property string configFile: String(
    settings && settings.localConfigFile
      ? settings.localConfigFile
      : "~/.config/omarchy/local-ai-pi-copilot.toml"
  )
  readonly property int refreshInterval: Math.max(2, Number(
    settings && settings.refreshIntervalSec ? settings.refreshIntervalSec : 5
  )) * 1000
  readonly property string home: Quickshell.env("HOME") || ""
  readonly property string defaultSuggestionPath: home + "/.local/state/omarchy/local-ai-pi-copilot/suggestion.json"
  readonly property string suggestionPath: String(status.suggestionFile || defaultSuggestionPath)
  readonly property var hostWindow: button.QsWindow.window

  property var status: ({
    configured: false, configError: "", enabled: false, active: false, paused: false,
    state: "disabled", model: "auto", endpoint: "", lastError: "",
    suggestionFile: "", playbookFile: "", delegateAvailable: false,
    privacy: { windowTitle: true, screenshots: false, denyRules: 0 }
  })
  property var suggestion: ({})
  property bool busy: false
  property string feedback: ""
  property bool feedbackIsError: false
  property string pendingAction: ""
  property double clockMs: Date.now()

  readonly property bool enabled: status.enabled === true
  readonly property bool active: status.active === true
  readonly property bool paused: status.paused === true
  readonly property bool failed: status.state === "error" || String(status.lastError || "") !== ""
  readonly property bool suggestionVisible: suggestion && suggestion.id
    && Number(suggestion.expiresAt || 0) * 1000 > clockMs
  readonly property string stateLabel: {
    if (busy) return "Updating…"
    if (!status.configured) return "Setup needed"
    if (!enabled) return "Off"
    if (paused) return "Paused"
    if (status.state === "thinking") return "Thinking…"
    if (status.state === "suggesting") return "Suggestion ready"
    if (failed) return "Needs attention"
    if (active) return "Watching"
    return "Waiting"
  }

  visible: true
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  function refresh() {
    if (!statusProcess.running) statusProcess.running = true
  }

  function clearFeedback() {
    feedbackTimer.stop()
    feedback = ""
    feedbackIsError = false
  }

  function showFeedback(message) {
    feedback = message
    feedbackIsError = false
    feedbackTimer.restart()
  }

  function showError(message) {
    feedback = message
    feedbackIsError = true
    feedbackTimer.stop()
  }

  function runAction(action) {
    if (actionProcess.running) return
    busy = true
    pendingAction = action
    clearFeedback()
    actionProcess.command = [controlPath, "--config", configFile, action]
    actionProcess.running = true
  }

  function applyStatus(value) {
    if (!value || typeof value !== "object") return
    status = value
    if (value.suggestion && value.suggestion.id) suggestion = value.suggestion
    suggestionFile.reload()
  }

  function applySuggestion(text) {
    try {
      var value = JSON.parse(String(text || "{}"))
      suggestion = value && typeof value === "object" ? value : ({})
    } catch (error) {
      suggestion = ({})
    }
  }

  function successMessage(action) {
    if (action === "enable") return "Copilot enabled"
    if (action === "disable") return "Copilot disabled"
    if (action === "pause") return "Copilot paused"
    if (action === "resume") return "Copilot resumed"
    if (action === "dismiss") return "Suggestion dismissed"
    if (action === "copy") return "Suggestion copied"
    if (action === "remember") return "Playbook rule saved"
    if (action === "delegate") return "Task opened in the heavy harness"
    if (action === "test-suggestion") return "Test suggestion shown"
    if (action === "restart") return "Copilot restarted"
    return "Copilot updated"
  }

  onOpenedChanged: if (opened) {
    clearFeedback()
    refresh()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  Component.onCompleted: refresh()

  Timer {
    interval: root.refreshInterval
    running: true
    repeat: true
    onTriggered: root.refresh()
  }

  Timer {
    interval: 1000
    running: root.suggestionVisible
    repeat: true
    onTriggered: root.clockMs = Date.now()
  }

  Timer {
    id: feedbackTimer
    interval: 3500
    onTriggered: {
      root.feedback = ""
      root.feedbackIsError = false
    }
  }

  Timer {
    id: actionRefresh
    interval: 600
    onTriggered: root.refresh()
  }

  FileView {
    id: suggestionFile
    path: root.suggestionPath
    watchChanges: true
    printErrors: false
    onLoaded: root.applySuggestion(text())
    onFileChanged: reload()
  }

  Process {
    id: statusProcess
    running: false
    command: [root.controlPath, "--config", root.configFile, "status"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          root.applyStatus(JSON.parse(String(text || "{}")))
        } catch (error) {
          root.showError("Could not read Copilot status")
        }
      }
    }
    stderr: StdioCollector { id: statusError; waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode !== 0) {
        var detail = String(statusError.text || "Could not read Copilot status").trim()
        root.showError(detail.length > 180 ? detail.slice(0, 177) + "…" : detail)
      }
    }
  }

  Process {
    id: actionProcess
    running: false
    stdout: StdioCollector { id: actionOutput; waitForEnd: true }
    stderr: StdioCollector { id: actionError; waitForEnd: true }
    onExited: function(exitCode) {
      root.busy = false
      if (exitCode === 0) root.showFeedback(root.successMessage(root.pendingAction))
      else {
        var detail = String(actionError.text || actionOutput.text || "Copilot action failed").trim()
        root.showError(detail.length > 220 ? detail.slice(0, 217) + "…" : detail)
      }
      root.pendingAction = ""
      actionRefresh.restart()
      suggestionFile.reload()
    }
  }

  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): string { root.refresh(); return "ok" }
    function enable(): string { root.runAction("enable"); return "ok" }
    function disable(): string { root.runAction("disable"); return "ok" }
    function pause(): string { root.runAction("pause"); return "ok" }
    function resume(): string { root.runAction("resume"); return "ok" }
    function status(): string { return root.stateLabel }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󰚩"
    tooltipText: "Local AI Copilot · " + root.stateLabel
    active: root.active && !root.paused
    useActiveColor: false

    Rectangle {
      visible: root.enabled || root.failed
      width: Style.space(5)
      height: width
      radius: width / 2
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      anchors.rightMargin: Style.space(2)
      anchors.bottomMargin: Style.space(2)
      color: root.failed ? root.urgent : (root.paused ? root.dim : root.accent)
    }

    onPressed: function(buttonCode) {
      if (buttonCode === Qt.RightButton) root.runAction(root.enabled ? "disable" : "enable")
      else if (buttonCode === Qt.MiddleButton && root.enabled) root.runAction(root.paused ? "resume" : "pause")
      else root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(400))
    contentHeight: panel.fittedContentHeight(content.implicitHeight, Style.space(620))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onActivateRequested: root.refresh()
      onCloseRequested: root.close()
      onTextKey: function(text) {
        if (text === "s" || text === "S") root.runAction(root.enabled ? "disable" : "enable")
        if ((text === "p" || text === "P") && root.enabled) root.runAction(root.paused ? "resume" : "pause")
      }

      Flickable {
        anchors.fill: parent
        contentWidth: width
        contentHeight: content.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: content
          width: parent.width
          spacing: Style.space(12)

          PanelHero {
            width: parent.width
            title: "Local AI Copilot"
            meta: "PI · LOCAL · OPT-IN"
            foreground: root.foreground
            fontFamily: root.fontFamily
            iconComponent: Component {
              Text {
                text: "󰚩"
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.display
              }
            }
          }

          Item {
            width: parent.width
            implicitHeight: Math.max(copilotState.implicitHeight, stateValue.implicitHeight)

            Text {
              id: copilotState
              anchors.left: parent.left
              anchors.right: stateValue.left
              anchors.rightMargin: Style.spacing.md
              text: root.active ? "Always-on observer" : "Copilot observer"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              font.bold: true
              elide: Text.ElideRight
            }

            Text {
              id: stateValue
              anchors.right: parent.right
              text: root.stateLabel
              color: root.failed ? root.urgent : (root.active && !root.paused ? root.foreground : root.dim)
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
          }

          Text {
            width: parent.width
            text: !root.status.configured
              ? String(root.status.configError || "Create the machine-local settings file")
              : String(root.status.model || "auto") + " · " + String(root.status.endpoint || "local endpoint")
            color: root.failed ? root.urgent : root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }

          Row {
            width: parent.width
            spacing: Style.spacing.md
            readonly property real cellWidth: (width - spacing) / 2

            Button {
              width: parent.cellWidth
              text: root.enabled ? "Turn off" : "Turn on"
              enabled: !root.busy && root.status.configured
              bordered: true
              foreground: root.foreground
              fontFamily: root.fontFamily
              fontSize: Style.font.bodySmall
              verticalPadding: Style.spacing.controlPaddingY
              onClicked: root.runAction(root.enabled ? "disable" : "enable")
            }

            Button {
              width: parent.cellWidth
              text: root.paused ? "Resume" : "Pause"
              enabled: !root.busy && root.enabled
              bordered: true
              foreground: root.foreground
              fontFamily: root.fontFamily
              fontSize: Style.font.bodySmall
              verticalPadding: Style.spacing.controlPaddingY
              onClicked: root.runAction(root.paused ? "resume" : "pause")
            }
          }

          PanelSeparator { width: parent.width; foreground: root.foreground }

          PanelSectionHeader {
            width: parent.width
            text: "BOUNDARIES"
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          Text {
            width: parent.width
            text: "Window metadata only · no screenshots · no tools · isolated Pi home"
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }

          Text {
            width: parent.width
            text: Number((root.status.privacy || {}).denyRules || 0) + " privacy deny rules · "
              + (root.status.delegateAvailable ? "heavy delegation available" : "no heavy harness connected")
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }

          PanelSeparator { width: parent.width; foreground: root.foreground }

          PanelSectionHeader {
            width: parent.width
            text: "SETUP & TEST"
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          Grid {
            width: parent.width
            columns: 2
            spacing: Style.spacing.md
            readonly property real cellWidth: (width - spacing) / 2

            Button {
              width: parent.cellWidth
              text: "Test suggestion"
              enabled: !root.busy
              bordered: true
              foreground: root.foreground
              fontFamily: root.fontFamily
              fontSize: Style.font.bodySmall
              verticalPadding: Style.spacing.controlPaddingY
              onClicked: root.runAction("test-suggestion")
            }

            Button {
              width: parent.cellWidth
              text: "Restart observer"
              enabled: !root.busy && root.enabled
              bordered: true
              foreground: root.foreground
              fontFamily: root.fontFamily
              fontSize: Style.font.bodySmall
              verticalPadding: Style.spacing.controlPaddingY
              onClicked: root.runAction("restart")
            }

            Button {
              width: parent.cellWidth
              text: "Edit settings"
              enabled: !root.busy && root.status.configured
              bordered: true
              foreground: root.foreground
              fontFamily: root.fontFamily
              fontSize: Style.font.bodySmall
              verticalPadding: Style.spacing.controlPaddingY
              onClicked: root.runAction("edit-settings")
            }

            Button {
              width: parent.cellWidth
              text: "Edit playbook"
              enabled: !root.busy && root.status.configured
              bordered: true
              foreground: root.foreground
              fontFamily: root.fontFamily
              fontSize: Style.font.bodySmall
              verticalPadding: Style.spacing.controlPaddingY
              onClicked: root.runAction("open-playbook")
            }
          }

          Text {
            width: parent.width
            text: root.feedback !== "" ? root.feedback : String(root.status.lastError || "")
            visible: text !== ""
            color: root.feedbackIsError || root.failed ? root.urgent : root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
          }
        }
      }
    }
  }

  PanelWindow {
    id: suggestionWindow
    visible: root.suggestionVisible
    screen: root.hostWindow ? root.hostWindow.screen : null
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "local-ai-pi-copilot-suggestion"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    mask: Region { item: suggestionCard }

    BorderSurface {
      id: suggestionCard
      width: Math.min(Style.space(410), suggestionWindow.width - Style.gapsOut * 2)
      implicitHeight: suggestionContent.implicitHeight + borderTop + borderBottom + Style.space(24)
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      anchors.rightMargin: Style.gapsOut + (root.bar && root.bar.position === "right" ? root.bar.barSize : 0)
      anchors.bottomMargin: Style.gapsOut + (root.bar && root.bar.position === "bottom" ? root.bar.barSize : 0)
      color: Color.notifications.background
      borderSpec: Border.surfaceSpec("notifications", "border", Color.notifications.border, Math.max(1, Style.space(2)))
      radius: Style.cornerRadius
      clip: true

      Column {
        id: suggestionContent
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: Style.space(12)
        spacing: Style.space(8)

        Row {
          width: parent.width
          spacing: Style.space(8)

          Text {
            text: "󰚩"
            color: Color.notifications.text
            font.family: root.fontFamily
            font.pixelSize: Style.font.icon
          }

          Text {
            width: parent.width - Style.space(34)
            text: String(root.suggestion.title || "Local AI Copilot")
            color: Color.notifications.text
            font.family: root.fontFamily
            font.pixelSize: Style.font.title
            font.bold: true
            wrapMode: Text.WordWrap
            maximumLineCount: 2
            elide: Text.ElideRight
          }
        }

        Text {
          width: parent.width
          text: String(root.suggestion.body || "")
          color: Qt.darker(Color.notifications.text, 1.15)
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          wrapMode: Text.WordWrap
          maximumLineCount: 4
          elide: Text.ElideRight
        }

        Text {
          width: parent.width
          text: String((root.suggestion.context || {}).appId || "Desktop")
            + " · " + Math.round(Number(root.suggestion.confidence || 0) * 100) + "%"
          color: Qt.darker(Color.notifications.text, 1.45)
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }

        Grid {
          width: parent.width
          columns: 2
          spacing: Style.space(8)
          readonly property real cellWidth: (width - spacing) / 2

          Button {
            width: parent.cellWidth
            text: "Dismiss"
            bordered: true
            foreground: Color.notifications.text
            fontFamily: root.fontFamily
            fontSize: Style.font.bodySmall
            verticalPadding: Style.spacing.controlPaddingY
            onClicked: root.runAction("dismiss")
          }

          Button {
            width: parent.cellWidth
            text: "Copy draft"
            bordered: true
            foreground: Color.notifications.text
            fontFamily: root.fontFamily
            fontSize: Style.font.bodySmall
            verticalPadding: Style.spacing.controlPaddingY
            onClicked: root.runAction("copy")
          }

          Button {
            width: parent.cellWidth
            text: "Remember"
            bordered: true
            foreground: Color.notifications.text
            fontFamily: root.fontFamily
            fontSize: Style.font.bodySmall
            verticalPadding: Style.spacing.controlPaddingY
            onClicked: root.runAction("remember")
          }

          Button {
            width: parent.cellWidth
            visible: root.status.delegateAvailable && String(root.suggestion.delegatePrompt || "") !== ""
            text: "Delegate…"
            bordered: true
            foreground: Color.notifications.text
            fontFamily: root.fontFamily
            fontSize: Style.font.bodySmall
            verticalPadding: Style.spacing.controlPaddingY
            onClicked: root.runAction("delegate")
          }
        }
      }
    }
  }
}
