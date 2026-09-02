pragma ComponentBehavior: Bound

import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import QtQuick
import "effects"

// Draws an animated background above the wallpaper and below every window.
// The wallpaper renderer is untouched: this owns click-through surfaces on the
// Bottom layer directly above it, so transitions and gestures keep working.
Item {
  id: root

  // Injected by the host, after Component.onCompleted. Not safe during construction.
  property var shell
  property var manifest

  readonly property string pluginId:
    manifest && manifest.id ? String(manifest.id) : "ivanskodje.animated-backgrounds"

  readonly property string home: Quickshell.env("HOME")
  readonly property string stateDir: home + "/.local/state/omarchy/current"
  readonly property string pluginDir:
    decodeURIComponent(String(Qt.resolvedUrl(".")).replace(/^file:\/\//, "")).replace(/\/$/, "")

  // Not watched directly: the renderer owns the "background" IpcHandler and a
  // FileView on the symlink would read the whole image. Duck-typed, forks differ.
  readonly property var backgroundService: {
    if (!shell)
      return null
    if (typeof shell.serviceFor === "function") {
      var direct = shell.serviceFor("omarchy.background")
      if (direct && typeof direct.currentBackground === "string")
        return direct
    }
    if (!shell._services)
      return null
    for (var id in shell._services) {
      var svc = shell._services[id]
      if (svc && typeof svc.currentBackground === "string")
        return svc
    }
    return null
  }

  readonly property bool bound: backgroundService !== null
  property string polledWallpaper: ""
  readonly property string wallpaper: bound ? backgroundService.currentBackground : polledWallpaper

  // A marker image selects its effect. Any other wallpaper turns the plugin off.
  readonly property string effect: {
    var m = String(wallpaper).split("/").pop().toLowerCase().match(/^animated-(grid|rain)\./)
    return m ? m[1] : ""
  }

  onWallpaperChanged: {
    theme.reload()
    installMarkers()
  }

  function installMarkers() {
    if (!settings.markers || markerProc.running)
      return
    markerProc.command = ["/usr/bin/timeout", "-k", "5", "30",
                          "/usr/bin/bash", pluginDir + "/markers.sh", "install", pluginDir]
    markerProc.running = true
  }

  Component.onCompleted: installMarkers()

  Process {
    id: markerProc
    clearEnvironment: true
    environment: ({ HOME: root.home })
    onExited: function(exitCode) {
      if (exitCode !== 0)
        console.warn("animated-backgrounds: markers.sh exited " + exitCode
                     + "; the effects will not appear in the background switcher")
    }
  }

  ThemePalette {
    id: theme
    source: root.stateDir + "/theme/colors.toml"
  }

  // Inline on this plugin's shell.json entry, which is where the shell requires
  // plugin settings to live. The entry exists while the plugin is enabled, and
  // shellConfig is replaced on save, so every key here hot-reloads.
  QtObject {
    id: settings

    readonly property var entry: {
      var entries = root.shell && root.shell.shellConfig
        && Array.isArray(root.shell.shellConfig.plugins) ? root.shell.shellConfig.plugins : []
      for (var i = 0; i < entries.length; i++)
        if (entries[i] && String(entries[i].id) === root.pluginId)
          return entries[i]
      return ({})
    }

    readonly property int fps: Number(entry.fps) > 0 ? Number(entry.fps) : 20
    readonly property string rainStyle: entry.rainStyle === "light" ? "light" : "dense"
    readonly property bool markers: entry.markers !== false
    readonly property bool poll: entry.poll === true
    readonly property bool pauseWhenCovered: entry.pauseWhenCovered === true
    readonly property bool themeColors: entry.themeColors !== false
  }

  // updateEntryInline replaces the entry, so merge over the current values.
  function persist(patch) {
    if (!shell || typeof shell.updateEntryInline !== "function")
      return
    var next = { id: root.pluginId }
    for (var k in settings.entry)
      if (k !== "id") next[k] = settings.entry[k]
    for (var p in patch)
      next[p] = patch[p]
    shell.updateEntryInline(root.pluginId, next)
  }

  // Timing lives here, not in SynthwaveGrid: one driver for every screen, so the
  // surfaces commit in the same pass instead of drifting against each other.
  property real gridPhase: 0
  readonly property real gridCycleMs: 1200   // ms for one grid row to reach the viewer

  Timer {
    interval: Math.max(16, Math.round(1000 / settings.fps))
    repeat: true
    running: root.effect === "grid" && !root.covered
    onTriggered: root.gridPhase = (root.gridPhase + interval / root.gridCycleMs) % 1
  }

  // Where the sky surface ends and the floor surface begins. Both window heights
  // need it before either scene exists, and one pixel out shows a seam.
  readonly property real gridHorizonFrac: 0.56

  // Off by default: gaps and transparency mean the desktop is rarely truly hidden
  // and a stopped background reads as a glitch. All screens, since phase is shared.
  readonly property bool covered: {
    if (!settings.pauseWhenCovered)
      return false
    var mons = Hyprland.monitors.values
    if (mons.length === 0)
      return false
    for (var i = 0; i < mons.length; i++) {
      var ws = mons[i].activeWorkspace
      if (!ws || ws.toplevels.values.length === 0)
        return false
    }
    return true
  }

  // Fallback for a host that injects no `shell`. Idle whenever the binding works.
  Timer {
    interval: 2000
    repeat: true
    triggeredOnStart: true
    running: !root.bound || settings.poll
    onTriggered: if (!probe.running) probe.running = true
  }

  Process {
    id: probe
    clearEnvironment: true
    environment: ({ HOME: root.home })
    command: ["/usr/bin/timeout", "-k", "5", "10",
              "/usr/bin/readlink", "-f", root.stateDir + "/background"]
    stdout: StdioCollector {
      // Ignore an empty read: ln -nsf leaves a brief window with no target.
      onStreamFinished: {
        var s = String(text || "").trim()
        if (s)
          root.polledWallpaper = s
      }
    }
  }

  IpcHandler {
    target: "animated-background"

    function refresh(): void {
      theme.reload()
      root.installMarkers()
      if (!probe.running)
        probe.running = true
    }

    // One verb per setting, always returning the resulting value. Quickshell
    // refuses a call with no arguments, so reading needs an explicit `get`.
    function themeColors(value: string): string {
      if (value === "true" || value === "false")
        root.persist({ themeColors: value === "true" })
      else if (value === "toggle")
        root.persist({ themeColors: !settings.themeColors })
      else if (value !== "get")
        return "usage: themeColors get|true|false|toggle"
      return settings.themeColors ? "true" : "false"
    }

    function rainStyle(value: string): string {
      if (value === "dense" || value === "light")
        root.persist({ rainStyle: value })
      else if (value === "toggle")
        root.persist({ rainStyle: settings.rainStyle === "light" ? "dense" : "light" })
      else if (value !== "get")
        return "usage: rainStyle get|dense|light|toggle"
      return settings.rainStyle
    }

    function pauseWhenCovered(value: string): string {
      if (value === "true" || value === "false")
        root.persist({ pauseWhenCovered: value === "true" })
      else if (value === "toggle")
        root.persist({ pauseWhenCovered: !settings.pauseWhenCovered })
      else if (value !== "get")
        return "usage: pauseWhenCovered get|true|false|toggle"
      return settings.pauseWhenCovered ? "true" : "false"
    }

    // No toggle: a frame rate has no opposite.
    function fps(value: string): string {
      if (value !== "get") {
        var n = Number(value)
        if (!(n > 0))
          return "usage: fps get|<positive number>"
        root.persist({ fps: Math.round(n) })
      }
      return String(settings.fps)
    }
  }

  // Three surfaces per screen, at most two of them shown: a static sky and an
  // animated floor for the grid, one full-screen surface for the rain.
  Variants {
    model: Quickshell.screens

    Scope {
      id: screenScope
      required property var modelData

      // Rounded once here so the two grid surfaces abut exactly.
      readonly property int horizonY: Math.round(modelData.height * root.gridHorizonFrac)

      // Grid, above the horizon. Static, so this surface never repaints.
      SceneWindow {
        screen: screenScope.modelData
        anchors { top: true; left: true; right: true }
        implicitHeight: screenScope.horizonY
        shown: root.effect === "grid"

        scene: Component {
          SynthwaveGrid {
            region: "sky"
            sceneWidth: screenScope.modelData.width
            sceneHeight: screenScope.modelData.height
            horizonY: screenScope.horizonY
            colors: settings.themeColors ? theme : null
          }
        }
      }

      // Grid, below the horizon. The only part that moves.
      SceneWindow {
        screen: screenScope.modelData
        anchors { bottom: true; left: true; right: true }
        implicitHeight: screenScope.modelData.height - screenScope.horizonY
        shown: root.effect === "grid"

        scene: Component {
          SynthwaveGrid {
            region: "floor"
            sceneWidth: screenScope.modelData.width
            sceneHeight: screenScope.modelData.height
            horizonY: screenScope.horizonY
            phase: root.gridPhase
            colors: settings.themeColors ? theme : null
          }
        }
      }

      // Rain. Nothing in it is static, so it is not worth splitting.
      SceneWindow {
        screen: screenScope.modelData
        anchors { top: true; bottom: true; left: true; right: true }
        shown: root.effect === "rain"

        scene: Component {
          DigitalRain {
            running: !root.covered
            style: settings.rainStyle
            colors: settings.themeColors ? theme : null
          }
        }
      }
    }
  }
}
