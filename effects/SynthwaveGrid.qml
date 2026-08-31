pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Shapes

// Synthwave horizon: gradient sky, banded sun, and a perspective grid floor.
// Two regions on two surfaces split at the horizon, since Qt Quick repaints a
// whole window when any node in it changes. Coordinates are screen space.
Item {
  id: scene

  // "sky" or "floor".
  property string region: "sky"

  // Each region is smaller than the screen, but the sun, the horizon and the row
  // projection are all defined against the whole.
  property real sceneWidth: width
  property real sceneHeight: height

  // Supplied by the caller, which needs it to size the two windows before either
  // scene exists.
  property int horizonY: Math.round(sceneHeight * 0.56)

  // Driven externally so every screen shares one timer and one value.
  property real phase: 0

  // ---- Tunables ------------------------------------------------------
  property int rows: 24              // horizontal lines in flight
  property real perspective: 3.0     // higher = gentler falloff, more visible depth
  property real floorSpan: 22        // how far past the panel edge the floor reaches
  property real colSpacing: 430      // px between vertical lines at the bottom edge
  property real colGrowth: 1.28      // spacing growth once a line is off-screen
  property real bottomFade: 0.52     // fraction of the floor faded out at the near edge
  property real sunFrac: 0.26        // sun radius as a fraction of panel height
  // --------------------------------------------------------------------

  // Role source, normally a ThemePalette. Null keeps the Synthwave '84 defaults.
  // Not named `palette`: QQuickItem has one, and it shadows silently.
  property var colors: null

  property color skyTop: colors ? colors.skyTop : "#180024"
  property color skyHorizon: colors ? colors.skyHorizon : "#5c1466"
  property color floorNear: colors ? colors.floorNear : "#12001c"
  property color gridColor: colors ? colors.gridColor : "#ff00ff"
  property color glowColor: colors ? colors.glowColor : "#ff7edb"
  property color sunTop: colors ? colors.sunTop : "#f3e70f"
  property color sunMid: colors ? colors.sunMid : "#fe5442"
  property color sunLow: colors ? colors.sunLow : "#ff2d95"
  property color starColor: colors ? colors.starColor : "#ffffff"

  readonly property real gridHeight: Math.max(1, sceneHeight - horizonY)
  readonly property real sunRadius: sceneHeight * sunFrac
  readonly property real sunCenterY: horizonY - sunRadius * 0.88
  readonly property real bloomHeight: Math.max(10, sceneHeight * 0.022)

  // Normalised so the furthest row lands exactly on the horizon. Raw 1/d never
  // arrives: over a 634px floor, 70 rows still stop 26px short.
  readonly property real fFar: perspective / (perspective + rows - 1)

  // Screen-space y of the row at depth d.
  function rowY(d) {
    var f = (perspective / (perspective + d - 1) - fFar) / (1 - fFar)
    return horizonY + gridHeight * f
  }

  // The sky is a plain vertical lerp, so a slit cut in the sun can be filled
  // with the exact colour that would show through it — no mask layer needed.
  function skyColorAt(y) {
    var t = Math.max(0, Math.min(1, y / Math.max(1, horizonY)))
    return Qt.rgba(skyTop.r + (skyHorizon.r - skyTop.r) * t,
                   skyTop.g + (skyHorizon.g - skyTop.g) * t,
                   skyTop.b + (skyHorizon.b - skyTop.b) * t, 1)
  }

  // Sun slits: position and thickness as fractions of the sun's diameter,
  // widening toward the bottom the way the poster art does.
  readonly property var slits: [
    { p: 0.55, h: 0.022 }, { p: 0.638, h: 0.030 }, { p: 0.730, h: 0.039 },
    { p: 0.828, h: 0.049 }, { p: 0.933, h: 0.060 }
  ]

  // Spacing grows geometrically once a line leaves the panel: filling the top
  // corners at uniform spacing would take ~700 lines.
  function verticalPath() {
    var vx = sceneWidth / 2, out = ""
    var limit = sceneWidth * floorSpan, edge = sceneWidth * 0.5
    var o = 0, step = colSpacing

    out += "M " + vx + " 0 L " + vx + " " + gridHeight + " "
    while (o < limit && out.length < 60000) {
      o += step
      out += "M " + vx + " 0 L " + (vx + o) + " " + gridHeight + " "
      out += "M " + vx + " 0 L " + (vx - o) + " " + gridHeight + " "
      if (o > edge) step *= colGrowth
    }
    return out
  }

  Loader {
    anchors.fill: parent
    active: scene.region === "sky"
    sourceComponent: skyRegion
  }

  Loader {
    anchors.fill: parent
    active: scene.region === "floor"
    sourceComponent: floorRegion
  }

  Component {
    id: skyRegion

    Item {
      anchors.fill: parent

      // Must stay the same lerp as skyColorAt(), which the sun slits sample to
      // fill themselves with the sky behind.
      Rectangle {
        anchors.fill: parent
        gradient: Gradient {
          GradientStop { position: 0.0; color: scene.skyTop }
          GradientStop { position: 1.0; color: scene.skyHorizon }
        }
      }

      // Static starfield, seeded once. Stars sit behind the sun.
      Repeater {
        model: 170

        Rectangle {
          required property int index
          // Deterministic scatter so a restart doesn't reshuffle the sky.
          readonly property real rx: (Math.sin(index * 12.9898) * 43758.5453) % 1
          readonly property real ry: (Math.sin(index * 78.233) * 43758.5453) % 1
          readonly property real rs: (Math.sin(index * 39.425) * 43758.5453) % 1

          width: Math.abs(rs) < 0.15 ? 2 : 1
          height: width
          radius: width / 2
          x: Math.abs(rx) * scene.sceneWidth
          y: Math.abs(ry) * scene.horizonY * 0.92
          color: scene.starColor
          opacity: 0.22 + Math.abs(rs) * 0.55
        }
      }

      // The disc overhangs the horizon by about 0.12 of its radius and relies on
      // the surface edge to trim it.
      Item {
        id: sun
        x: scene.sceneWidth / 2 - scene.sunRadius
        y: scene.sunCenterY - scene.sunRadius
        width: scene.sunRadius * 2
        height: scene.sunRadius * 2

        Rectangle {
          anchors.fill: parent
          radius: width / 2
          gradient: Gradient {
            GradientStop { position: 0.00; color: scene.sunTop }
            GradientStop { position: 0.42; color: scene.sunMid }
            GradientStop { position: 1.00; color: scene.sunLow }
          }
        }

        Repeater {
          model: scene.slits

          Rectangle {
            id: slit
            required property var modelData
            // Chord across the slit's span, so it never paints past the disc.
            // The widest edge is the top below centre and the bottom above it.
            readonly property real dyTop: (modelData.p - 0.5) * sun.height
            readonly property real dyBottom: (modelData.p + modelData.h - 0.5) * sun.height
            readonly property real dy: Math.min(Math.abs(dyTop), Math.abs(dyBottom))
            readonly property real half: Math.sqrt(Math.max(0, scene.sunRadius * scene.sunRadius - dy * dy))

            // `parent` here is `sun`, so sampling the sky behind needs sun.y too.
            readonly property real absTop: sun.y + y

            x: sun.width / 2 - half
            width: half * 2
            y: modelData.p * sun.height
            height: modelData.h * sun.height
            gradient: Gradient {
              GradientStop { position: 0.0; color: scene.skyColorAt(slit.absTop) }
              GradientStop { position: 1.0; color: scene.skyColorAt(slit.absTop + slit.height) }
            }
          }
        }
      }

      // The bloom straddles the split, so each surface draws all of it and lets
      // its own edge clip it.
      Rectangle {
        y: scene.horizonY - height * 0.55
        width: scene.sceneWidth
        height: scene.bloomHeight
        gradient: Gradient {
          GradientStop { position: 0.0; color: Qt.rgba(scene.glowColor.r, scene.glowColor.g, scene.glowColor.b, 0) }
          GradientStop { position: 0.55; color: Qt.rgba(scene.glowColor.r, scene.glowColor.g, scene.glowColor.b, 0.38) }
          GradientStop { position: 1.0; color: Qt.rgba(scene.glowColor.r, scene.glowColor.g, scene.glowColor.b, 0) }
        }
      }
    }
  }

  // Everything below the horizon, in surface-local coordinates: screen y minus
  // `horizonY`.
  Component {
    id: floorRegion

    Item {
      anchors.fill: parent

      Rectangle {
        anchors.fill: parent
        gradient: Gradient {
          GradientStop { position: 0.0; color: scene.skyHorizon }
          GradientStop { position: 0.75; color: scene.floorNear }
          GradientStop { position: 1.0; color: scene.floorNear }
        }
      }

      // Lower half of the bloom; the sky surface draws the upper half.
      Rectangle {
        y: -height * 0.55
        width: scene.sceneWidth
        height: scene.bloomHeight
        gradient: Gradient {
          GradientStop { position: 0.0; color: Qt.rgba(scene.glowColor.r, scene.glowColor.g, scene.glowColor.b, 0) }
          GradientStop { position: 0.55; color: Qt.rgba(scene.glowColor.r, scene.glowColor.g, scene.glowColor.b, 0.38) }
          GradientStop { position: 1.0; color: Qt.rgba(scene.glowColor.r, scene.glowColor.g, scene.glowColor.b, 0) }
        }
      }

      // Vertical lines converge on the vanishing point, so they never move.
      Shape {
        anchors.fill: parent
        antialiasing: true
        preferredRendererType: Shape.CurveRenderer
        opacity: 0.75

        ShapePath {
          strokeColor: scene.gridColor
          strokeWidth: 1.3
          fillColor: "transparent"
          PathSvg { path: scene.verticalPath() }
        }
      }

      // Rows sit one unit apart in depth and `phase` slides them from 1 toward 0,
      // so on wrap row i+1 lands where row i began and the loop is seamless.
      Repeater {
        model: scene.rows

        Item {
          id: row
          required property int index
          readonly property real d: (index + 1) - scene.phase
          readonly property real ly: scene.rowY(d)
          readonly property real near: Math.max(0, Math.min(1, (ly - scene.horizonY) / scene.gridHeight))

          // Snap to whole device pixels: at a fractional y a 1px line splits
          // across two rows, and the split shifts every frame, which is flicker.
          visible: ly < scene.sceneHeight + 6
          y: Math.round(ly) - scene.horizonY
          width: scene.sceneWidth
          height: thickness + 6

          readonly property int thickness: Math.max(1, Math.round(1 + 2.6 * row.near))

          // Bloom, so the grid reads as neon rather than wireframe.
          Rectangle {
            y: -2
            width: parent.width
            height: parent.thickness + 4
            antialiasing: false
            color: scene.glowColor
            opacity: 0.16 * Math.min(1, row.near / 0.3)
          }

          Rectangle {
            width: parent.width
            height: parent.thickness
            color: scene.gridColor
            antialiasing: false
            // Ramp from zero so a new row fades in instead of popping on.
            opacity: Math.min(1, 0.05 + row.near * 2.6)
          }
        }
      }

      // Under a tiled layout the only visible background is the strip below the
      // last window, where a near row crossing it reads as a blinking bar.
      Rectangle {
        y: scene.gridHeight - height
        width: scene.sceneWidth
        height: scene.gridHeight * scene.bottomFade
        gradient: Gradient {
          GradientStop { position: 0.0; color: Qt.rgba(scene.floorNear.r, scene.floorNear.g, scene.floorNear.b, 0.0) }
          GradientStop { position: 0.5; color: Qt.rgba(scene.floorNear.r, scene.floorNear.g, scene.floorNear.b, 0.5) }
          GradientStop { position: 1.0; color: Qt.rgba(scene.floorNear.r, scene.floorNear.g, scene.floorNear.b, 0.97) }
        }
      }
    }
  }
}
