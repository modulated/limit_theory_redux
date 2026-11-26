// Space dust fleck (port of Legacy effect/dustfleck.glsl; see
// vertex/billboard/dustfleck_draw.glsl for the draw-block contract): a soft
// streak, blue at its head and orange at its tail, faded out near the camera
// and toward the edge of the dust cube. Additive.
#include fragment
#include color
#include math
#include draw_block

#define cubeSize (drawUser[0].w)

void main() {
  // 0 at the camera, 1 at the cube's half size (Legacy: dist / 1024)
  float dist = length(pos - eye) / (0.5 * cubeSize);
  float alpha = exp(-pow2(2.0 * uv.x));
  alpha *= 0.1;
  alpha *= 1.0 - exp(-8.0 * uv.y);
  alpha *= 1.0 - exp(-8.0 * (1.0 - uv.y));
  alpha *= 1.0 - pow4(1.0 - uv.y);
  alpha *= exp(-4.0 * max(0.0, dist - 0.8));
  alpha *= 1.0 - exp(-16.0 * max(0.0, dist - 0.1));
  vec3 c = 1.0 / mix(
    vec3(0.1, 0.5, 1.0),
    vec3(1.0, 0.5, 0.1),
    1.0 - uv.y);
  c = c / lum(c);
  c *= sqrt(c);
  outColor = vec4(c * alpha, 1.0);
  FRAGMENT_CORRECT_DEPTH;
}
