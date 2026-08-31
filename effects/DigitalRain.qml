pragma ComponentBehavior: Bound

import QtQuick

// Animated digital rain for the desktop background.
// Cost tracks how many things move and how much area they cover, not how many
// glyphs there are, so `tickMs` and `cellSize` are the expensive dials.
Item {
  id: rain

  // "dense" is the wall of code from the film. "light" is sparse and airy:
  // fewer, slower streams with long gaps between passes.
  property string style: "dense"
  property bool running: true

  readonly property bool dense: style !== "light"

  // ---- Tunables ------------------------------------------------------
  property int cellSize:       dense ? 31 : 30     // glyph cell in px
  property int trailCells:     dense ? 35 : 20     // glyphs per stream
  property int bands:          3                   // opacity steps per stream
  property int tickMs:         dense ? 75 : 70     // ms per grid step
  property real minSpeed:      dense ? 0.35 : 0.30 // cells per tick
  property real maxSpeed:      dense ? 1.60 : 1.10
  property int gapCells:       dense ? 8 : 45      // idle before a stream restarts
  // Flicker budget, split in two because a changed glyph is nearly free but every
  // column it lands in has to have its cached texture redrawn.
  property int rerollColumns:  dense ? 7 : 3
  property int rerollsPerColumn: dense ? 4 : 3
  property real tailOpacity:   dense ? 0.22 : 0.12 // dimmest band
  // --------------------------------------------------------------------

  // Role source, normally a ThemePalette. Null keeps the defaults.
  // Not named `palette`: QQuickItem has one, and it shadows silently.
  property var colors: null

  property color bodyColor: colors ? colors.rainBody : "#3cbf5c"
  // The leading glyph is the hot head of the stream, well above the body colour.
  property color headColor: colors ? colors.rainHead : "#d7f5d8"
  property color groundColor: colors ? colors.background : "#0b0b0b"

  readonly property string glyphs: "ｱｲｳｴｵｶｷｸｹｺｻｼｽｾｿﾀﾁﾂﾃﾄﾅﾆﾇﾈﾉﾊﾋﾌﾍﾎﾏﾐﾑﾒﾓﾔﾕﾖﾗﾘﾙﾚﾛﾜﾝ0123456789"

  readonly property int cellsPerBand: Math.max(1, Math.floor((trailCells - 1) / bands))
  readonly property int bodyCells: cellsPerBand * bands
  readonly property int columnCount: Math.max(1, Math.ceil(width / cellSize))
  readonly property int rowCount: Math.max(1, Math.ceil(height / cellSize))

  property var columnCache: []

  function columns() {
    if (columnCache.length !== columnCount) {
      var a = []
      for (var i = 0; i < columnCount; i++) {
        var it = columnRepeater.itemAt(i)
        // Mid-construction: leave the cache empty and try again next tick.
        if (!it)
          return []
        a.push(it)
      }
      columnCache = a
    }
    return columnCache
  }

  function randomGlyph() {
    return glyphs.charAt(Math.floor(Math.random() * glyphs.length))
  }

  function randomRun(n) {
    var s = randomGlyph()
    for (var i = 1; i < n; i++) s += "\n" + randomGlyph()
    return s
  }

  // The film's glyphs are mirrored katakana, and flipping the layer is cheaper
  // than transforming every node.
  transform: Scale { origin.x: rain.width / 2; xScale: -1 }

  // Glyphs are painted on transparency, so without this the marker still shows
  // through the layer.
  Rectangle {
    anchors.fill: parent
    color: rain.groundColor
  }

  Repeater {
    id: columnRepeater
    model: rain.columnCount

    Item {
      id: column
      required property int index

      // Head position in cells, fractional so columns advance at their own
      // rate off a shared tick.
      property real pos: 0
      property real speed: 1
      property real tone: 1
      property int lastRow: -99999

      x: index * rain.cellSize
      width: rain.cellSize
      height: (rain.bodyCells + 1) * rain.cellSize

      // A column's transform changes every tick, so it is its own scene-graph
      // batch root: nothing merges with it and its geometry is rebuilt each frame.
      layer.enabled: true

      function respawn(initial) {
        speed = rain.minSpeed + Math.random() * (rain.maxSpeed - rain.minSpeed)
        // Brightness, not length: varying length would mean rebuilding nodes.
        tone = 0.55 + Math.random() * 0.45
        pos = initial ? Math.random() * (rain.rowCount + rain.trailCells)
                      : -Math.random() * rain.gapCells
      }

      function step() {
        pos += speed
        // Restart once the tail has cleared the bottom edge.
        if (pos - rain.bodyCells - 1 > rain.rowCount) respawn(false)
        var row = Math.round(pos)
        if (row !== lastRow) {
          lastRow = row
          y = (row - rain.bodyCells) * rain.cellSize
        }
        // Assigned rather than bound: a binding would re-evaluate for every
        // column on every tick.
        var vis = y + height > 0 && y < rain.height
        if (vis !== visible)
          visible = vis
      }

      function reroll(n) {
        for (var k = 0; k < n; k++) {
          var band = bandRepeater.itemAt(Math.floor(Math.random() * rain.bands))
          if (band) band.reroll()
        }
      }

      Component.onCompleted: { respawn(true); step() }

      Repeater {
        id: bandRepeater
        model: rain.bands

        Text {
          id: band
          required property int index

          // Glyph k of the run sits at string offset 2k — every glyph is one
          // UTF-16 unit and they are joined by single newlines.
          function reroll() {
            var at = Math.floor(Math.random() * rain.cellsPerBand) * 2
            text = text.substring(0, at) + rain.randomGlyph() + text.substring(at + 1)
          }

          y: index * rain.cellsPerBand * rain.cellSize
          width: rain.cellSize
          horizontalAlignment: Text.AlignHCenter
          font.family: "Noto Sans CJK JP"
          font.pixelSize: rain.cellSize * 0.85
          lineHeight: rain.cellSize
          lineHeightMode: Text.FixedHeight
          color: rain.bodyColor
          opacity: column.tone * (rain.tailOpacity
                   + (1 - rain.tailOpacity) * (index + 1) / rain.bands)
          text: rain.randomRun(rain.cellsPerBand)
        }
      }

      Text {
        y: rain.bodyCells * rain.cellSize
        width: rain.cellSize
        height: rain.cellSize
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        font.family: "Noto Sans CJK JP"
        font.pixelSize: rain.cellSize * 0.85
        color: rain.headColor
        text: rain.randomGlyph()
      }
    }
  }

  Timer {
    interval: rain.tickMs
    repeat: true
    running: rain.running && rain.visible
    onTriggered: {
      var cols = rain.columns()
      var i, n = cols.length
      for (i = 0; i < n; i++)
        cols[i].step()
      for (i = 0; i < rain.rerollColumns && n > 0; i++)
        cols[Math.floor(Math.random() * n)].reroll(rain.rerollsPerColumn)
    }
  }
}
