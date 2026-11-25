// Space dust flecks (the port of Legacy Effects/Dust's flecks, which drew
// billboard/wrapped.glsl x effect/dustfleck.glsl with loose uniforms): a
// fixed cloud of points that wraps around the camera in a cube, each drawn
// as a streak along the camera's motion. Draw-block contract, shared with
// fragment/effect/dustfleck_draw.glsl:
//   drawUser[0] = (wrap offset .xyz: the camera position mod the cube, cube size)
//   drawUser[1] = (motion axis .xyz, streak length)
//   drawUser[2] = (streak width, -, -, -)
// The mesh: four vertices per fleck at its point, uv.x -1..1 across the
// streak, uv.y 0..1 along it.
#include vertex_scene
#include math

#define wrapOffset (drawUser[0].xyz)
#define cubeSize (drawUser[0].w)
#define axis (drawUser[1].xyz)
#define streakLength (drawUser[1].w)
#define streakWidth (drawUser[2].x)

void main() {
  VS_BEGIN
  // The fleck's place relative to the camera, wrapped into the cube around it
  vec3 rel = mod(vertPos - wrapOffset + 0.5 * cubeSize, vec3(cubeSize)) - 0.5 * cubeSize;
  vec4 wp = vec4(eye + rel, 1.0);
  vec3 toCam = normalize(eye - wp.xyz + vec3(1e-6));
  vec3 side = cross(toCam, axis);
  float sideLength = length(side);
  vec3 right = sideLength > 1e-4 ? side / sideLength : vec3(1.0, 0.0, 0.0);
  wp.xyz += streakWidth * uv.x * right;
  wp.xyz += streakLength * uv.y * axis;
  pos = wp.xyz;
  gl_Position = mProj * (mView * wp);
  VS_END
}
