pragma ComponentBehavior: Bound

import QtQuick

// PlayStation Doom fire, the scatter from Fabien Sanglard's article, run on the GPU.
Item {
  id: fire

  property bool running: true
  property int fps: 20

  // Role source, normally a ThemePalette. Null keeps the Doom palette.
  property var colors: null

  readonly property int targetRows: 140
  readonly property var shades: [
    0x07, 0x07, 0x07, 0x1f, 0x07, 0x07, 0x2f, 0x0f, 0x07, 0x47, 0x0f, 0x07,
    0x57, 0x17, 0x07, 0x67, 0x1f, 0x07, 0x77, 0x1f, 0x07, 0x8f, 0x27, 0x07,
    0x9f, 0x2f, 0x07, 0xaf, 0x3f, 0x07, 0xbf, 0x47, 0x07, 0xc7, 0x47, 0x07,
    0xdf, 0x4f, 0x07, 0xdf, 0x57, 0x07, 0xdf, 0x57, 0x07, 0xd7, 0x5f, 0x07,
    0xd7, 0x5f, 0x07, 0xd7, 0x67, 0x0f, 0xcf, 0x6f, 0x0f, 0xcf, 0x77, 0x0f,
    0xcf, 0x7f, 0x0f, 0xcf, 0x87, 0x17, 0xc7, 0x87, 0x17, 0xc7, 0x8f, 0x17,
    0xc7, 0x97, 0x1f, 0xbf, 0x9f, 0x1f, 0xbf, 0x9f, 0x1f, 0xbf, 0xa7, 0x27,
    0xbf, 0xa7, 0x27, 0xbf, 0xaf, 0x2f, 0xb7, 0xaf, 0x2f, 0xb7, 0xb7, 0x2f,
    0xb7, 0xb7, 0x37, 0xcf, 0xcf, 0x6f, 0xdf, 0xdf, 0x9f, 0xef, 0xef, 0xc7,
    0xff, 0xff, 0xff
  ]

  readonly property int cell: Math.max(1, Math.floor(height / targetRows))
  readonly property int cols: Math.max(2, Math.floor(width / cell))
  readonly property int rows: Math.max(2, Math.floor(height / cell))

  // Must match MAX_STEPS in shaders/fire.frag. Each snapshot costs Qt an extra presented frame.
  readonly property int snapshotSteps: 8

  // The fire on screen is at `step`; the newest snapshot holds it at `base`, or holds nothing until `lit`.
  property int step: 0
  property int base: 0
  property bool lit: false
  property bool pending: false
  property bool latestB: false
  // Without it, screens lit together would burn identical flames.
  property int salt: Math.floor(Math.random() * 4096)

  onColsChanged: relight()
  onRowsChanged: relight()
  // heatB, snapshotB, heatA and snapshotA sample each other, so unless the cycle is cut here Qt keeps a deleted window referenced and the next update() crashes.
  Window.onWindowChanged: {
    if (Window.window) {
      snapshotA.heat = Qt.binding(function() { return heatB })
    } else {
      snapshotA.heat = null
      relight()
    }
  }

  function relight() {
    step = 0
    base = 0
    lit = false
    salt = Math.floor(Math.random() * 4096)
  }

  function stepIndex(n) {
    return Qt.point(n % 4096, (Math.floor(n / 4096) + salt) % 4096)
  }

  function advance() {
    if (step + 1 - base < snapshotSteps) {
      step++
      return
    }
    // The last snapshot has not rendered yet, so the next one would read a texture that does not hold it.
    if (pending)
      return
    var into = latestB ? snapshotA : snapshotB
    var layer = latestB ? heatA : heatB
    into.base = stepIndex(base)
    into.origin = lit ? 0 : 1
    pending = true
    layer.scheduleUpdate()
    latestB = !latestB
    step++
    base = step
    lit = true
  }

  ShaderEffect {
    id: snapshotA
    width: fire.cols
    height: fire.rows
    blending: false

    property var heat: heatB
    property var shades: shadeSource
    property size cells: Qt.size(fire.cols, fire.rows)
    property point base: Qt.point(0, 0)
    property real steps: fire.snapshotSteps
    property real origin: 1
    property real draw: 0

    fragmentShader: Qt.resolvedUrl("shaders/fire.frag.qsb")
  }

  ShaderEffect {
    id: snapshotB
    width: fire.cols
    height: fire.rows
    blending: false

    property var heat: heatA
    property var shades: shadeSource
    property size cells: Qt.size(fire.cols, fire.rows)
    property point base: Qt.point(0, 0)
    property real steps: fire.snapshotSteps
    property real origin: 1
    property real draw: 0

    fragmentShader: Qt.resolvedUrl("shaders/fire.frag.qsb")
  }

  // Not live: a snapshot renders only when scheduled, never because something else repainted.
  ShaderEffectSource {
    id: heatA
    sourceItem: snapshotA
    hideSource: true
    visible: false
    live: false
    smooth: false
    textureSize: Qt.size(fire.cols, fire.rows)
    onScheduledUpdateCompleted: fire.pending = false
  }

  ShaderEffectSource {
    id: heatB
    sourceItem: snapshotB
    hideSource: true
    visible: false
    live: false
    smooth: false
    textureSize: Qt.size(fire.cols, fire.rows)
    onScheduledUpdateCompleted: fire.pending = false
  }

  Row {
    id: shadeRow

    Repeater {
      model: 37

      Rectangle {
        required property int index
        width: 1
        height: 1
        color: fire.colors ? fire.colors.fireShades[index]
                           : Qt.rgba(fire.shades[index * 3] / 255, fire.shades[index * 3 + 1] / 255,
                                     fire.shades[index * 3 + 2] / 255, 1)
      }
    }
  }

  ShaderEffectSource {
    id: shadeSource
    sourceItem: shadeRow
    hideSource: true
    visible: false
    smooth: false
    textureSize: Qt.size(37, 1)
  }

  ShaderEffect {
    anchors.fill: parent
    blending: false

    property var heat: fire.latestB ? heatB : heatA
    property var shades: shadeSource
    property size cells: Qt.size(fire.cols, fire.rows)
    property point base: fire.stepIndex(fire.base)
    property real steps: fire.step - fire.base
    property real origin: fire.lit ? 0 : 1
    property real draw: 1

    fragmentShader: Qt.resolvedUrl("shaders/fire.frag.qsb")
  }

  Timer {
    interval: Math.max(16, Math.round(1000 / fire.fps))
    repeat: true
    running: fire.running && fire.visible && fire.width > 2 && fire.height > 2
    onTriggered: fire.advance()
  }
}
