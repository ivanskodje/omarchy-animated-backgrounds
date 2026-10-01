pragma ComponentBehavior: Bound

import QtQuick

// PlayStation Doom fire, the scatter from Fabien Sanglard's article.
// Each cell writes one neighbor above and cools by zero or one. Unwritten
// cells keep their heat, which is what separates the tongues. The buffer is
// about 140 rows and drawn nearest-neighbor, so the cells stay square.
Item {
  id: fire

  property bool running: true

  readonly property int targetRows: 140
  readonly property var palette: [
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

  property var heat: null
  property int cols: 2
  property int rows: 2

  function ensureSize() {
    var cell = Math.max(1, Math.floor(height / targetRows))
    var nextCols = Math.max(2, Math.floor(width / cell))
    var nextRows = Math.max(2, Math.floor(height / cell))
    if (heat && nextCols === cols && nextRows === rows && heat.length === nextCols * nextRows)
      return

    cols = nextCols
    rows = nextRows
    var next = new Array(nextCols * nextRows)
    for (var i = 0; i < next.length; i++)
      next[i] = 0
    var bottom = (nextRows - 1) * nextCols
    for (var x = 0; x < nextCols; x++)
      next[bottom + x] = 36
    heat = next
  }

  function step() {
    if (width < 2 || height < 2)
      return
    ensureSize()
    var w = cols
    var h = heat
    var len = h.length
    var src, rand, shift, index, cooled
    for (src = 0; src < len; src++) {
      rand = Math.round(Math.random() * 3) & 3
      shift = rand === 0 ? -1 : rand === 3 ? 1 : 0
      index = src - w + shift
      if (index < 0)
        index = 0
      if (index >= len)
        continue
      cooled = h[src] - (rand & 1)
      h[index] = cooled > 0 ? cooled : 0
    }
    var bottom = (rows - 1) * w
    for (var x = 0; x < w; x++)
      h[bottom + x] = 36
    canvas.requestPaint()
  }

  Rectangle {
    anchors.fill: parent
    color: "#070707"
  }

  Canvas {
    id: canvas
    anchors.fill: parent
    antialiasing: false
    renderStrategy: Canvas.Immediate

    onPaint: {
      var h = fire.heat
      if (!h || h.length === 0)
        return
      var ctx = getContext("2d")
      if (!ctx)
        return

      var w = fire.cols
      var r = fire.rows
      var cellW = width / w
      var cellH = height / r
      var colors = fire.palette
      var y, x, run, index, at
      ctx.reset()
      for (y = 0; y < r; y++) {
        run = h[y * w]
        at = 0
        for (x = 1; x <= w; x++) {
          index = x < w ? h[y * w + x] : -1
          if (index === run)
            continue
          var p = run * 3
          ctx.fillStyle = Qt.rgba(colors[p] / 255, colors[p + 1] / 255, colors[p + 2] / 255, 1)
          ctx.fillRect(at * cellW, y * cellH, (x - at) * cellW, cellH)
          at = x
          run = index
        }
      }
    }
  }

  Timer {
    interval: 33
    repeat: true
    running: fire.running && fire.visible && fire.width > 2 && fire.height > 2
    onTriggered: fire.step()
  }

  onWidthChanged: fire.step()
  onHeightChanged: fire.step()
}
