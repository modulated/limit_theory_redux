-- AUTO GENERATED. DO NOT MODIFY!
---@meta

---@class TargetSurface
TargetSurface = {}

-- The sampleable triangles of `mesh` (copied: the mesh may change or go).
---@param mesh Mesh
---@return TargetSurface
function TargetSurface.Create(mesh) end

-- Number of triangles the surface can be sampled on.
---@return integer
function TargetSurface:getTriangleCount() end

---@return number
function TargetSurface:getTotalArea() end

-- Sample an aim point, deterministic in `seed`. `viewX/Y/Z` point from
-- the target toward the shooter (zero to aim anywhere on the hull);
-- triangles whose normal faces the shooter by at least `minFacingDot`
-- are preferred. `out` takes the local position (0..2), the triangle's
-- normal (3..5) and its 1-based index (6).
---@param seed integer
---@param time number
---@param viewX number
---@param viewY number
---@param viewZ number
---@param minFacingDot number
---@param motionAmplitude number
---@param motionFrequency number
---@param out number[]
---@param out_size integer
function TargetSurface:sample(seed, time, viewX, viewY, viewZ, minFacingDot, motionAmplitude, motionFrequency, out, out_size) end
