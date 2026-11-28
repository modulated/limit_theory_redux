// An engine's jet (EnginePlumeSystem), drawn on an axis billboard behind the
// nozzle: uv.y runs 0 at the nozzle to -1 at the tip, uv.x -1..1 across.
//
// A white-hot core along the axis, short and bright, inside a wider glow in
// the engine's colour; the jet narrows toward its tip and fades out there;
// it flickers; at full throttle shock diamonds pulse near the nozzle.
//
//   drawUser[0]  colour (xyz), alpha (w)
//   drawUser[1]  half-width (x), length (y) -- the vertex stage's size
//   drawUser[2]  throttle (x: 0 idle, 1 full, 1.5 travel drive), seed (y), time (z)
#include fragment
#include math

#include draw_block

#define color (drawUser[0].xyz)
#define alpha (drawUser[0].w)
#define throttle (drawUser[2].x)
#define seed (drawUser[2].y)
#define time (drawUser[2].z)

void main() {
  float v = saturate(1.0 + uv.y);     // 1 at the nozzle, 0 at the tip
  float along = 1.0 - v;              // 0 at the nozzle, 1 at the tip

  // The jet narrows toward its tip
  float width = mix(1.0, 0.22, along);
  float u = abs(uv.x) / max(width, 0.05);

  // Flicker: two beats, and ripples running down the jet
  float flick = 0.88
      + 0.08 * sin(time * 37.0 + seed * 13.0) * sin(time * 23.0 + seed * 7.0)
      + 0.06 * sin(along * 24.0 - time * 30.0 + seed);

  // The hot core and the coloured glow round it
  float core = exp(-u * u * 38.0) * exp(-along * (6.0 - 2.0 * saturate(throttle)));
  float glow = exp(-u * u * 5.0) * pow(v, 1.4);

  // Shock diamonds near the nozzle, at full throttle
  float full = smoothstep(0.6, 1.0, throttle);
  float diamonds = 1.0 + 0.45 * full * pow(0.5 + 0.5 * cos(along * 42.0), 6.0) * exp(-along * 3.5);

  vec3 c = color;
  c *= c / max(avg(c), 1e-3);
  vec3 hot = mix(c, vec3(1.0), 0.8);
  vec3 col = (glow * c * 1.5 + core * hot * 3.2) * diamonds * flick;

  // The tip fades out rather than ending
  col *= smoothstep(0.0, 0.25, v);

  outColor = vec4(col * alpha, 1.0);
  FRAGMENT_CORRECT_DEPTH;
}
