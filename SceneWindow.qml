import Quickshell
import Quickshell.Wayland
import QtQuick

// One click-through layer surface: a whole effect, or one region of one.
PanelWindow {
  id: win

  // A Component, so an unselected effect is never built, and so the remap pulse
  // below does not tear a running one down. Hence `active: shown`, not `visible`.
  property Component scene: null
  property bool shown: false

  WlrLayershell.namespace: "animated-background"
  WlrLayershell.layer: WlrLayer.Bottom
  WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
  exclusionMode: ExclusionMode.Ignore
  color: "transparent"

  // Empty input region, or the surface swallows the wallpaper's double click
  // gestures, which are what open the background and theme switchers.
  mask: Region {}

  // Never destroyed, only hidden. updatesEnabled is left alone: a parked layer
  // surface can lose its buffer and leave a black desktop.
  visible: shown && !remapGuard.remapping

  ScreenRemapGuard {
    id: remapGuard
    window: win
  }

  Loader {
    anchors.fill: parent
    active: win.shown
    sourceComponent: win.scene
  }
}
