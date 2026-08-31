import QtQuick

// Hyprland leaves a mapped layer surface at its old global position when its
// monitor moves. Pulse `remapping` so the owning window unmaps and remaps it.
// Vendored from Omarchy's Ui/ScreenMoveRemap.qml to avoid the dependency.
Item {
  id: root

  required property var window
  readonly property var screen: window ? window.screen : null

  // Fold into the window binding: visible: <shown> && !guard.remapping
  property bool remapping: false

  visible: false

  // A layout reshuffle can move the monitor more than once before it lands, so
  // let the positions settle before the single remap pulse.
  Timer {
    id: settleTimer
    interval: 200
    onTriggered: root.remapping = true
  }

  // Hold the surface unmapped for a beat so the compositor processes the unmap
  // before the remap instead of coalescing them into a no-op.
  Timer {
    interval: 50
    running: root.remapping
    onTriggered: root.remapping = false
  }

  Connections {
    target: root.screen
    function onXChanged() { settleTimer.restart() }
    function onYChanged() { settleTimer.restart() }
  }
}
