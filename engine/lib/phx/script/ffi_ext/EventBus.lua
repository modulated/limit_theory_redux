local libphx = require('libphx').lib
local Converter = require('Core.Util.Converter')
local PayloadConverter = require('Core.Util.PayloadConverter')

-- Event id -> name, for the profiler scope names (custom events add theirs
-- in EventBus:register).
local eventNames = {}

local function eventScopeName(event)
    local name = eventNames[event]
    if name then return name end
    if Event then
        for k, v in pairs(Event) do
            if v == event and type(k) == "string" then
                eventNames[event] = k
                return k
            end
        end
    end
    return tostring(event)
end

-- Who a handler belongs to: the subscriber's class name (Class/Subclass
-- put the class in the instance's metatable, and the class prints as its
-- name), else where the callback was defined.
local function subscriberName(ctxTable, callback)
    if type(ctxTable) == "table" then
        local cls = getmetatable(ctxTable)
        local clsMt = type(cls) == "table" and getmetatable(cls)
        if clsMt and clsMt.__tostring then
            return tostring(cls)
        end
    end
    local info = debug.getinfo(callback, "S")
    if info then
        return string.format("%s:%d", info.short_src:match("[^/\\]+$") or info.short_src, info.linedefined)
    end
    return "?"
end

function onDef_EventBus_t(t, mt)
    -- TODO: should return a handler
    ---@class EventBus
    ---@field register fun(self: EventBus, event: string, eventName: string, frameStage: FrameStage<integer>, rustPayload: boolean|nil)
    ---@field subscribe fun(self: EventBus, event: string, ctxTable: table|nil, callback: function): integer
    ---@field unsubscribe fun(self: EventBus, tunnelId: integer)
    ---@field send fun(self: EventBus, event: string, ctxTable: table|nil, payload: Payload|number|boolean|string|nil)
    ---@field dispatch fun(self: EventBus, event: string, payload: Payload|nil)
    ---@field nextEvent fun(self: EventBus): (EventData?, any?)

    mt.__index.register = function(self, event, eventName, frameStage, rustPayload)
        local rustPayload = rustPayload == nil or rustPayload
        eventNames[event] = eventName
        -- Log.Debug("Rust payload: " .. tostring(rustPayload))
        libphx.EventBus_Register(self, event, eventName, frameStage, rustPayload)
    end

    mt.__index.subscribe = function(self, event, ctxTable, callback)
        local entityId = ctxTable and ctxTable.getGuid and ctxTable:getGuid()
        local entityIdPtr = Converter.ToValuePtr(entityId, "uint64")

        local tunnelId = libphx.EventBus_Subscribe(self, event, entityIdPtr)
        -- Each handler is a profiler scope ("Lua.<Subscriber>.<Event>") so
        -- every Lua system shows up in the profile (F10 / the stats server's
        -- /profile.json). Off, it costs one lock-free flag read per call.
        if Profiler then
            local scope = string.format("Lua.%s.%s",
                subscriberName(ctxTable, callback), eventScopeName(event))
            local isEnabled, beginScope, endScope = Profiler.IsEnabled, Profiler.Begin, Profiler.End
            EventTunnels[tunnelId] = function(...)
                if isEnabled() then
                    beginScope(scope)
                    callback(ctxTable, ...)
                    endScope()
                else
                    callback(ctxTable, ...)
                end
            end
        else
            EventTunnels[tunnelId] = function(...) callback(ctxTable, ...) end
        end
        return tunnelId
    end

    mt.__index.unsubscribe = function(self, tunnelId)
        libphx.EventBus_Unsubscribe(self, tunnelId)
        EventTunnels[tunnelId] = nil
    end

    mt.__index.send = function(self, event, ctxTable, payload)
        local entityId = ctxTable and ctxTable.getGuid and ctxTable:getGuid()
        local entityIdPtr = Converter.ToValuePtr(entityId, "uint64")
        local rustPayload = self:hasRustPayload(event)
        libphx.EventBus_Send(self, event, entityIdPtr, PayloadConverter:valueToPayload(payload, rustPayload))
    end

    mt.__index.dispatch = function(self, event, payload)
        local rustPayload = self:hasRustPayload(event)
        libphx.EventBus_Send(self, event, nil, PayloadConverter:valueToPayload(payload, rustPayload))
    end

    mt.__index.nextEvent = function(self)
        local eventData = libphx.EventBus_NextEvent(self)
        if eventData == nil then
            return nil, nil
        end

        local payload = eventData:payload()
        local payloadValue = nil
        if payload ~= nil then
            payloadValue = PayloadConverter:payloadToValue(payload)
        end
        return eventData, payloadValue
    end
end
