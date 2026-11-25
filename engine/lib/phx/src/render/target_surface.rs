//! Aim points on a ship's hull: the triangles of a generated mesh, sampled
//! by area, for the weapons to aim at (`WeaponSystem:sampleTargetPoint`).
//!
//! This is the per-mount, per-frame work that used to be a Lua loop over
//! every triangle of the target's mesh, building a candidate table and
//! summing areas on each call (see `doc/engine/lua-workers.md`, A). The
//! triangles and their cumulative areas are computed once here, at build
//! time; a sample is then a facing pass plus a binary search, with no
//! allocation and no Lua RNG object.
//!
//! Sampling is deterministic in the seed given (a SplitMix64 stream), so a
//! mount's aim point is reproducible, as it was in Lua.

use glam::Vec3;

use crate::render::Mesh;

/// Degenerate triangles (zero area) are dropped at build time.
const AREA_EPSILON: f32 = 1e-9;

/// One triangle of the hull, in the mesh's local coordinates.
struct Triangle {
    p0: Vec3,
    p1: Vec3,
    p2: Vec3,
    normal: Vec3,
    area: f32,
}

/// The sampleable surface of one mesh.
pub struct TargetSurface {
    tris: Vec<Triangle>,
    /// Cumulative area over `tris`; the last entry is the total.
    cdf: Vec<f32>,
}

/// SplitMix64: a seed in, a stream of uniforms out. Small and allocation
/// free, so a sample costs nothing but arithmetic.
struct Rng(u64);

impl Rng {
    fn next_u64(&mut self) -> u64 {
        self.0 = self.0.wrapping_add(0x9E3779B97F4A7C15);
        let mut z = self.0;
        z = (z ^ (z >> 30)).wrapping_mul(0xBF58476D1CE4E5B9);
        z = (z ^ (z >> 27)).wrapping_mul(0x94D049BB133111EB);
        z ^ (z >> 31)
    }

    /// Uniform in [0, 1).
    fn uniform(&mut self) -> f32 {
        ((self.next_u64() >> 40) as f32) * (1.0 / 16777216.0)
    }
}

fn clamp(v: f32, lo: f32, hi: f32) -> f32 {
    v.max(lo).min(hi)
}

impl TargetSurface {
    /// The triangles of `mesh`, with their normals and cumulative areas.
    pub fn from_mesh(mesh: &Mesh) -> Self {
        let vertices = mesh.get_vertex_data();
        let indices = mesh.get_index_data();
        let mut tris = Vec::with_capacity(indices.len() / 3);
        let mut cdf = Vec::with_capacity(indices.len() / 3);
        let mut total = 0.0f32;

        for tri in indices.chunks_exact(3) {
            let (i0, i1, i2) = (tri[0], tri[1], tri[2]);
            if i0 < 0 || i1 < 0 || i2 < 0 {
                continue;
            }
            let (i0, i1, i2) = (i0 as usize, i1 as usize, i2 as usize);
            if i0 >= vertices.len() || i1 >= vertices.len() || i2 >= vertices.len() {
                continue;
            }
            let (p0, p1, p2) = (vertices[i0].p, vertices[i1].p, vertices[i2].p);
            let cross = (p1 - p0).cross(p2 - p0);
            let double_area = cross.length();
            if double_area <= AREA_EPSILON {
                continue;
            }
            let area = double_area * 0.5;
            total += area;
            tris.push(Triangle {
                p0,
                p1,
                p2,
                normal: cross / double_area,
                area,
            });
            cdf.push(total);
        }

        Self { tris, cdf }
    }

    pub fn len(&self) -> usize {
        self.tris.len()
    }

    pub fn is_empty(&self) -> bool {
        self.tris.is_empty()
    }

    /// The total area of the surface.
    pub fn total_area(&self) -> f32 {
        self.cdf.last().copied().unwrap_or(0.0)
    }

    /// The first triangle whose cumulative area passes `pick`.
    fn search_cdf(&self, pick: f32) -> usize {
        let mut lo = 0usize;
        let mut hi = self.cdf.len() - 1;
        while lo < hi {
            let mid = (lo + hi) / 2;
            if self.cdf[mid] < pick {
                lo = mid + 1;
            } else {
                hi = mid;
            }
        }
        lo
    }

    /// Pick a triangle facing `view` (a unit vector from the target toward
    /// the shooter), by area. `view` of zero length, or a facing pass that
    /// finds nothing, falls back to the whole surface.
    fn pick_triangle(&self, rng: &mut Rng, view: Vec3, min_facing_dot: f32) -> usize {
        if view.length_squared() > 0.0 {
            // Pass one: the area facing the shooter. Pass two: the pick.
            let mut facing_area = 0.0f32;
            for t in self.tris.iter() {
                if t.normal.dot(view) >= min_facing_dot {
                    facing_area += t.area;
                }
            }
            if facing_area > 0.0 {
                let pick = rng.uniform() * facing_area;
                let mut accumulated = 0.0f32;
                let mut last = usize::MAX;
                for (index, t) in self.tris.iter().enumerate() {
                    if t.normal.dot(view) >= min_facing_dot {
                        accumulated += t.area;
                        last = index;
                        if pick <= accumulated {
                            return index;
                        }
                    }
                }
                if last != usize::MAX {
                    return last;
                }
            }
        }
        // Whole surface: the precomputed cumulative areas.
        self.search_cdf(rng.uniform() * self.total_area())
    }

    /// Sample a point on the hull. `out` takes the point's local position
    /// (0..2), its triangle's normal (3..5) and the triangle's 1-based index
    /// (6), the index as Lua had it.
    #[allow(clippy::too_many_arguments)]
    pub fn sample_into(
        &self,
        seed: u64,
        time: f32,
        view: Vec3,
        min_facing_dot: f32,
        motion_amplitude: f32,
        motion_frequency: f32,
        out: &mut [f32; 7],
    ) {
        if self.tris.is_empty() {
            *out = [0.0; 7];
            return;
        }
        let mut rng = Rng(seed);
        let index = self.pick_triangle(&mut rng, view, min_facing_dot);
        let t = &self.tris[index];

        // Barycentric weights, uniform over the triangle, then the slow
        // wobble that keeps the aim point moving over the hull.
        let root = rng.uniform().sqrt();
        let second = rng.uniform();
        let mut w1 = root * (1.0 - second);
        let mut w2 = root * second;
        let amplitude = clamp(motion_amplitude, 0.0, 0.25);
        let phase = rng.uniform() * std::f32::consts::TAU;
        w1 = clamp(
            w1 + amplitude * (time * motion_frequency * std::f32::consts::TAU + phase).sin(),
            0.02,
            0.94,
        );
        w2 = clamp(
            w2 + amplitude
                * (time * motion_frequency * std::f32::consts::PI * 1.82 + phase * 1.37).cos(),
            0.02,
            0.94,
        );
        if w1 + w2 > 0.96 {
            let s = 0.96 / (w1 + w2);
            w1 *= s;
            w2 *= s;
        }
        let w0 = 1.0 - w1 - w2;
        let position = t.p0 * w0 + t.p1 * w1 + t.p2 * w2;

        out[0] = position.x;
        out[1] = position.y;
        out[2] = position.z;
        out[3] = t.normal.x;
        out[4] = t.normal.y;
        out[5] = t.normal.z;
        out[6] = (index + 1) as f32;
    }
}

#[luajit_ffi_gen::luajit_ffi]
impl TargetSurface {
    /// The sampleable triangles of `mesh` (copied: the mesh may change or go).
    #[bind(name = "Create")]
    pub fn create(mesh: &Mesh) -> TargetSurface {
        TargetSurface::from_mesh(mesh)
    }

    /// Number of triangles the surface can be sampled on.
    #[bind(name = "GetTriangleCount")]
    pub fn triangle_count(&self) -> u32 {
        self.len() as u32
    }

    #[bind(name = "GetTotalArea")]
    pub fn get_total_area(&self) -> f32 {
        self.total_area()
    }

    /// Sample an aim point, deterministic in `seed`. `viewX/Y/Z` point from
    /// the target toward the shooter (zero to aim anywhere on the hull);
    /// triangles whose normal faces the shooter by at least `minFacingDot`
    /// are preferred. `out` takes the local position (0..2), the triangle's
    /// normal (3..5) and its 1-based index (6).
    #[bind(name = "Sample")]
    #[allow(clippy::too_many_arguments)]
    pub fn sample(
        &self,
        seed: u64,
        time: f32,
        view_x: f32,
        view_y: f32,
        view_z: f32,
        min_facing_dot: f32,
        motion_amplitude: f32,
        motion_frequency: f32,
        out: &mut [f32; 7],
    ) {
        self.sample_into(
            seed,
            time,
            Vec3::new(view_x, view_y, view_z),
            min_facing_dot,
            motion_amplitude,
            motion_frequency,
            out,
        );
    }
}
