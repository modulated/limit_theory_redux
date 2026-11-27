#include fragment
#include deferred
#include math
#include color
#include noise
#include draw_block

#define time (drawUser[0].x)      // ring rotation time (per draw)

#group 1
layout(std140) uniform MaterialParams {
  float rMin;
  float rMax;
  float ringHeight;
  float seed;
  float rotationSpeed;
  float twistFactor;
  int enableDebug;
  int debugMode;
};

in vec3 objPos;

/* A planetary ring after Saturn's.

   Structure, inside out (each ring's own boundaries jittered by its seed):
     * C ring: faint and translucent, greyer;
     * B ring: the dense, bright heart, with faint dark radial "spokes";
     * Cassini division: a dark gap;
     * A ring: a little dimmer and cooler, with an Encke-like gap near its edge.
   All of it broken into fine ringlets by noise at several radial scales, with
   a few narrower gaps scattered through, and small colour shifts from ringlet
   to ringlet (reddish dusty bands, bluish icy ones).

   Light: the face toward the star is lit; seen from the other side the ring
   glows with what passes through it, so its translucent parts are the bright
   ones there. Seen against the star, the fine dust lights up (forward
   scattering). Opacity follows the optical depth along the line of sight,
   so the ring is thin and see-through face-on and solid edge-on.

   Sparkle: individual ice particles glint, tiny specks that twinkle, close up.
*/

// Per-ring random numbers come from an integer hash of the seed's bits, not
// from `noise()`. `noise()` is `fract(sin(x) * 4137.3)`: a change in the last
// bit of `sin(x)` moves the result anywhere in 0..1. An expression that only
// reads uniforms (the seed) can be folded by the driver, and it was not
// evaluated the same way on every draw: with identical uniforms, vertices,
// pipeline and destination, the gaps jumped between two layouts on random
// frames (BenchmarkPhases on wgpu, Vulkan and DX12; RMSE 11 to 17). Integer
// arithmetic is exact, so these values are the same however they are
// evaluated; only expressions that vary per fragment still use `noise()`.
uint ringHash(uint x) {
    x ^= x >> 16u;
    x *= 0x7feb352du;
    x ^= x >> 15u;
    x *= 0x846ca68bu;
    x ^= x >> 16u;
    return x;
}

// A number in [0, 1) for (index, channel) of this ring, exact in float.
float ringRandom(int index, int channel) {
    uint h = ringHash(floatBitsToUint(seed) ^ ringHash(uint(index * 8 + channel) + 0x9e3779b9u));
    return float(h >> 8u) * (1.0 / 16777216.0);
}

// A whole-number offset for a noise lookup (exact, see above).
float ringOffset(int index) {
    return floor(ringRandom(index, 5) * 4096.0);
}

// A number in [0, 1) for one cell of the sparkle grid, and channel.
float cellRandom(int cr, int ca, int channel) {
    uint h = ringHash(uint(cr) * 73856093u ^ ringHash(uint(ca) * 19349663u + uint(channel) * 83492791u)
                      ^ floatBitsToUint(seed));
    return float(h >> 8u) * (1.0 / 16777216.0);
}

// 1 inside [a, b], easing in and out over `soft`.
float band(float x, float a, float b, float soft) {
    return smoothstep(a - soft, a + soft, x) * (1.0 - smoothstep(b - soft, b + soft, x));
}

void main() {
    // --- Where in the ring ---
    float r = length(objPos.xz);
    float rNorm = clamp((r - rMin) / max(1e-6, rMax - rMin), 0.0, 1.0);
    // Inner parts orbit faster (Kepler), slowly enough to read as drift
    float spin = time * rotationSpeed * 0.02 * (1.6 - rNorm);
    float angle = atan(objPos.z, objPos.x) + spin;

    // --- The major structure ---
    float jitter = (ringRandom(1, 0) - 0.5) * 0.10;
    float cEnd = 0.26 + jitter;                          // C ring -> B ring
    float bEnd = 0.62 + jitter * 0.5;                    // B ring -> Cassini
    float cassini = 0.045 + 0.035 * ringRandom(1, 1);    // its width
    float aStart = bEnd + cassini;
    float encke = mix(aStart, 1.0, 0.72 + 0.14 * ringRandom(1, 2));

    // Optical depth (how much there is to see), band by band
    float tau = mix(0.18, 1.45, smoothstep(cEnd - 0.03, cEnd + 0.03, rNorm));   // C faint, B dense
    tau *= mix(1.0, 0.65, smoothstep(aStart - 0.01, aStart + 0.03, rNorm));    // A dimmer
    tau *= 1.0 - 0.94 * band(rNorm, bEnd, aStart, 0.006);                     // Cassini
    tau *= 1.0 - 0.90 * band(rNorm, encke - 0.006, encke + 0.006, 0.003);      // Encke

    // A few narrower gaps scattered through
    for (int i = 0; i < 6; i++) {
        float gp = 0.05 + 0.9 * ringRandom(2 + i, 0);
        float gw = 0.002 + 0.007 * ringRandom(2 + i, 1);
        tau *= 1.0 - (0.35 + 0.5 * ringRandom(2 + i, 2)) * band(rNorm, gp - gw, gp + gw, gw * 0.6);
    }

    // Ringlets: structure at several radial scales
    float ringlets = 0.55 * fSmoothNoise(rNorm * 40.0 + ringOffset(10), 2, 2.0)
                   + 0.30 * fSmoothNoise(rNorm * 220.0 + ringOffset(11), 2, 2.0)
                   + 0.15 * fSmoothNoise(rNorm * 1100.0 + ringOffset(12), 1, 2.0);
    tau *= 0.45 + 1.1 * ringlets;

    // Spokes: faint dark radial streaks across the B ring, turning with it
    float spokes = fSmoothNoise(vec2(angle * 14.0, rNorm * 3.0 + ringOffset(13)), 2, 2.0);
    float inB = band(rNorm, cEnd + 0.03, bEnd - 0.03, 0.03);
    tau *= 1.0 - inB * 0.22 * smoothstep(0.6, 0.85, spokes);

    // Soft inner and outer edges
    tau *= smoothstep(0.0, 0.025, rNorm) * (1.0 - smoothstep(0.985, 1.0, rNorm));
    tau = max(tau, 0.0);

    // --- Colour ---
    // Each ring has its own palette, from dusty grey-brown to icy white
    float icy = ringRandom(3, 0);
    vec3 dusty = vec3(0.50, 0.44, 0.38);
    vec3 tanColor = vec3(0.88, 0.77, 0.62);
    vec3 ice = vec3(0.90, 0.93, 0.98);
    vec3 baseColor = mix(dusty, mix(tanColor, ice, 0.35 + 0.3 * ringRandom(3, 1)), icy);
    vec3 color = baseColor;
    // C ring greyer and darker, A ring a touch cooler
    color = mix(color * vec3(0.78, 0.78, 0.82), color, smoothstep(cEnd - 0.04, cEnd + 0.04, rNorm));
    color = mix(color, color * vec3(0.94, 0.98, 1.06), smoothstep(aStart, aStart + 0.06, rNorm));
    // Ringlet to ringlet: reddish dusty bands, bluish icy ones
    float hue = fSmoothNoise(rNorm * 160.0 + ringOffset(14), 2, 2.0);
    color *= mix(vec3(1.08, 0.96, 0.86), vec3(0.92, 0.98, 1.08), hue);
    color *= 0.85 + 0.3 * fSmoothNoise(rNorm * 600.0 + ringOffset(15), 1, 2.0);

    // --- Light ---
    vec3 N = normalize(normal);
    vec3 L = normalize(starDir);          // toward the star
    vec3 toEye = eye - pos;
    float viewDist = length(toEye);
    vec3 V = toEye / max(viewDist, 1e-6); // toward the eye
    float nl = dot(N, L);
    float nv = dot(N, V);
    float mu = max(abs(nv), 0.06);        // how face-on it is seen

    // Opacity from the optical depth along the line of sight
    float alpha = 1.0 - exp(-tau / mu);

    float light;
    if (nl * nv >= 0.0) {
        // The lit face: brighter the more squarely the star hits it
        light = 0.30 + 0.85 * abs(nl);
    } else {
        // The dark face: what passes through, so thin parts glow and dense
        // parts go dark
        light = (0.12 + 0.55 * abs(nl)) * exp(-tau * 0.9);
    }
    // Against the star the dust lights up
    float forward = pow(max(dot(-V, L), 0.0), 10.0);
    light += forward * 0.9 * (1.0 - exp(-tau * 0.6));
    color *= light;

    // --- Sparkle: ice glinting, close up ---
    // The ring's width in the world (rMin and rMax are in its own space;
    // mWorld carries the body's scale)
    float worldScale = length(vec3(mWorld[0][0], mWorld[0][1], mWorld[0][2]));
    float ringWidth = (rMax - rMin) * worldScale;
    float nearFade = clamp(1.0 - viewDist / (ringWidth * 4.0), 0.0, 1.0);
    if (nearFade > 0.0 && tau > 0.05) {
        float radialCells = 1400.0;
        int cr = int(floor(rNorm * radialCells));
        float circumference = 6.2831853 * r / max(1e-6, rMax - rMin) * radialCells;
        int ca = int(floor((angle / 6.2831853 + 0.5) * circumference));
        float pick = cellRandom(cr, ca, 0);
        if (pick > 0.985) {
            float rate = 2.0 + 6.0 * cellRandom(cr, ca, 1);
            float phase = 6.2831853 * cellRandom(cr, ca, 2);
            float twinkle = pow(0.5 + 0.5 * sin(time * rate + phase), 6.0);
            // A glint wants the light coming off the ring toward the eye
            float glint = 0.4 + 0.6 * pow(max(dot(reflect(-L, N), V), 0.0), 4.0);
            vec3 tint = mix(vec3(1.0, 0.85, 0.7), vec3(0.75, 0.88, 1.0), cellRandom(cr, ca, 3));
            float s = twinkle * glint * nearFade;
            color += tint * s * 1.6;
            alpha = max(alpha, s * 0.9);
        }
    }

    // Far off, the ring fades rather than shimmer
    alpha *= clamp(1.0 - viewDist / 1e7, 0.0, 1.0);

    if (enableDebug != 0) {
        if (debugMode == 1) { color = vec3(rNorm); alpha = 1.0; }
        else if (debugMode == 2) { color = vec3(tau * 0.5); alpha = 1.0; }
    }

    setAlbedo(color);
    setAlpha(clamp(alpha, 0.0, 1.0));
    setNormal(N);
    setDepth();
    setMaterial(Material_NoShade);
}
