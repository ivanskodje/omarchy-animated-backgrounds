import QtQuick
import Quickshell.Io

// Reads the active theme's colors.toml and maps it onto the roles the effects
// need. Two key schemas exist, named and numbered, so every role names candidates
// in both; numbered slots carry no reliable hue, so roles normalise by luminance.
QtObject {
  id: themePalette

  // Set by the host.
  property string source: ""
  property var values: ({})

  function reload() {
    if (source) file.reload()
  }

  function parse(text) {
    var out = {}
    var lines = String(text || "").split("\n")
    for (var i = 0; i < lines.length; i++) {
      var m = lines[i].match(/^\s*([A-Za-z0-9_]+)\s*=\s*["']?(#[0-9A-Fa-f]{6,8})/)
      if (m) out[m[1]] = m[2].substring(0, 7)
    }
    return out
  }

  // First key present wins.
  function pick(names, fallback) {
    for (var i = 0; i < names.length; i++) {
      var v = values[names[i]]
      if (typeof v === "string" && v.length > 0) return v
    }
    return fallback
  }

  function relativeLuminance(c) {
    return 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b
  }

  function scaled(spec, target) {
    var c = Qt.darker(spec, 1.0)
    var l = relativeLuminance(c)
    if (l <= 0) return c
    var k = target / l
    return Qt.rgba(Math.min(1, c.r * k), Math.min(1, c.g * k), Math.min(1, c.b * k), 1)
  }

  // Cap brightness, so a hot palette does not overpower the composition.
  function dim(spec, max) {
    return relativeLuminance(Qt.darker(spec, 1.0)) > max ? scaled(spec, max) : Qt.darker(spec, 1.0)
  }

  // Raise brightness, so a very dark palette stays legible.
  function lift(spec, min) {
    return relativeLuminance(Qt.darker(spec, 1.0)) < min ? scaled(spec, min) : Qt.darker(spec, 1.0)
  }

  readonly property color background: pick(["background", "color0"], "#000000")
  readonly property color foreground: pick(["foreground", "color15", "color7"], "#e0e0e0")

  // A light theme cannot use the dark composition darkened. Darkening a
  // near-neutral background yields grey, and a horizon capped dark sits under a
  // pale sky as a bruise. Light themes mirror the scene instead.
  readonly property bool light: relativeLuminance(background) > 0.5

  // Push a colour clear of the background: brighter on a dark theme, darker on
  // a light one.
  function contrast(spec, darkMin, lightMax) {
    return light ? dim(spec, lightMax) : lift(spec, darkMin)
  }

  readonly property color skyTop: light ? Qt.lighter(background, 1.06) : Qt.darker(background, 1.7)
  // The horizon band moves toward the background, not away from it.
  readonly property color skyHorizon: light ? lift(pick(["green", "color2"], "#8f00ff"), 0.70)
                                            : dim(pick(["green", "color2"], "#8f00ff"), 0.105)
  readonly property color floorNear: light ? Qt.lighter(background, 1.14) : Qt.darker(background, 2.4)
  readonly property color gridColor: contrast(pick(["magenta", "color5"], "#ff00ff"), 0.18, 0.22)
  readonly property color glowColor: contrast(pick(["bright_magenta", "color13", "magenta", "color5"], "#ff7edb"), 0.30, 0.42)
  readonly property color sunTop: pick(["yellow", "color3"], "#f3e70f")
  readonly property color sunMid: pick(["orange", "bright_red", "color9", "red", "color1"], "#fe5442")
  readonly property color sunLow: pick(["bright_magenta", "color13", "magenta", "color5"], "#ff7edb")
  // Dark specks on a pale sky read as dirt, so on a light theme they stay faint.
  readonly property color starColor: light ? Qt.darker(background, 1.10) : foreground

  readonly property color rainBody: contrast(pick(["accent", "green", "color2"], "#3cbf5c"), 0.20, 0.45)
  readonly property color rainHead: contrast(foreground, 0.62, 0.12)

  property FileView file: FileView {
    path: themePalette.source
    // A theme switch replaces the directory wholesale, which drops a path watch
    // for good. The host calls reload() instead.
    watchChanges: false
    printErrors: false
    onLoaded: themePalette.values = themePalette.parse(text())
    onLoadFailed: themePalette.values = ({})
  }
}
