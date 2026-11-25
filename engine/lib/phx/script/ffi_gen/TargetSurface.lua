-- AUTO GENERATED. DO NOT MODIFY!
-- TargetSurface ---------------------------------------------------------------
local Loader = {}

function Loader.declareType()
    ffi.cdef [[
        typedef struct TargetSurface {} TargetSurface;
    ]]

    return 1, 'TargetSurface'
end

function Loader.defineType()
    local ffi = require('ffi')
    local libphx = require('libphx').lib
    local TargetSurface

    do -- C Definitions
        ffi.cdef [[
            void           TargetSurface_Free             (TargetSurface*);
            TargetSurface* TargetSurface_Create           (Mesh const* mesh);
            uint32         TargetSurface_GetTriangleCount (TargetSurface const*);
            float          TargetSurface_GetTotalArea     (TargetSurface const*);
            void           TargetSurface_Sample           (TargetSurface const*, uint64 seed, float time, float viewX, float viewY, float viewZ, float minFacingDot, float motionAmplitude, float motionFrequency, float* out, uint64 out_size);
        ]]
    end

    do -- Global Symbol Table
        TargetSurface = {
            Create           = function(mesh)
                local _instance = libphx.TargetSurface_Create(mesh)
                return Core.ManagedObject(_instance, libphx.TargetSurface_Free)
            end,
        }

        if onDef_TargetSurface then onDef_TargetSurface(TargetSurface, mt) end
        TargetSurface = setmetatable(TargetSurface, mt)
    end

    do -- Metatype for class instances
        local t  = ffi.typeof('TargetSurface')
        local mt = {
            __index = {
                getTriangleCount = libphx.TargetSurface_GetTriangleCount,
                getTotalArea     = libphx.TargetSurface_GetTotalArea,
                sample           = libphx.TargetSurface_Sample,
            },
        }

        if onDef_TargetSurface_t then onDef_TargetSurface_t(t, mt) end
        TargetSurface_t = ffi.metatype(t, mt)
    end

    return TargetSurface
end

return Loader
