#version 440

// A step copies each cell from one cell of the step before, so a cell's heat is a snapshot cell minus the cooling met walking back to it.

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
  mat4 qt_Matrix;
  float qt_Opacity;
  vec2 cells;
  vec2 base;
  float steps;
  float origin;
  float draw;
};

layout(binding = 1) uniform sampler2D heat;
layout(binding = 2) uniform sampler2D shades;

// Must match snapshotSteps in DoomFire.qml.
const int MAX_STEPS = 8;

// 0 to 3 weighted 1/6, 1/3, 1/3, 1/6 like round(random * 3). Hash without sine, David Hoskins, MIT, see docs/THIRD-PARTY-NOTICES.md.
float roll(vec2 cell, vec2 tick) {
  vec4 p = fract(vec4(cell, tick) * vec4(0.1031, 0.1030, 0.0973, 0.1099));
  p += dot(p, p.wzxy + 33.33);
  return floor(fract((p.x + p.y) * (p.z + p.w)) * 3.0 + 0.5);
}

void main() {
  vec2 at = floor(qt_TexCoord0 * cells);
  float cooled = 0.0;
  // Step numbers are split into halves below 4096 so the float math stays exact.
  vec2 tick = base + vec2(steps, 0.0);
  if (tick.x >= 4096.0)
    tick = vec2(tick.x - 4096.0, mod(tick.y + 1.0, 4096.0));

  for (int i = 0; i < MAX_STEPS; i++) {
    if (float(i) >= steps || at.y >= cells.y - 1.0)
      break;
    // Writers are the original's flat buffer neighbors, so they wrap across the side edges.
    vec2 right = at.x + 1.0 < cells.x ? at + vec2(1.0, 1.0) : vec2(0.0, at.y + 2.0);
    vec2 below = at + vec2(0.0, 1.0);
    vec2 left = at.x > 0.0 ? at + vec2(-1.0, 1.0) : vec2(cells.x - 1.0, at.y);
    // Roll 0 drifts left, 3 drifts right, odd rolls cool, and the last writer in buffer order wins.
    if (right.y < cells.y && roll(right, tick) < 0.5) {
      at = right;
    } else {
      float b = roll(below, tick);
      if (b > 0.5 && b < 2.5) {
        at = below;
        cooled += b < 1.5 ? 1.0 : 0.0;
      } else if (roll(left, tick) > 2.5) {
        at = left;
        cooled += 1.0;
      }
    }
    tick.x -= 1.0;
    if (tick.x < 0.0)
      tick = vec2(tick.x + 4096.0, mod(tick.y + 4095.0, 4096.0));
  }

  float stored = floor(texture(heat, (at + 0.5) / cells).r * 36.0 + 0.5);
  float h = at.y >= cells.y - 1.0 ? 36.0 : (origin > 0.5 ? 0.0 : stored);
  h = clamp(h - cooled, 0.0, 36.0);

  if (draw > 0.5)
    fragColor = texture(shades, vec2((h + 0.5) / 37.0, 0.5)) * qt_Opacity;
  else
    fragColor = vec4(h / 36.0, 0.0, 0.0, 1.0);
}
