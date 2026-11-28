--[[----------------------------------------------------------------------------
  Checks the Lua scripts for the mistakes that have cost the most:

    luajit tools/code-check.lua

  * Overriding the global `type`. It once named a class instance by its class,
    so `type(entity) == "table"` was false, every NPC ship was taken for dead
    and none was ever seen. `type` is Lua's own; ask what a value is with
    classOf / isInstance / isPlainTable (Core/Structures/Class.lua) or
    Entity.is (Core/ECS/Registry.lua).
  * Duck-typing an entity: `x.isValid ~= nil` and the like. A plain table can
    pass it, and a cdata Position errors on the missing field. Use Entity.is.
  * Comparing `type(...)` with a class name ("Entity", ...): never true.
  * Reading `__type` outside the class library: use classOf.

  Prints each finding as file:line and exits 1 when there is any (0 when
  clean), so it can run in CI.
------------------------------------------------------------------------------]]

local repoRoot = (function()
    local here = debug.getinfo(1, "S").source:match("^@(.*)[/\\]tools[/\\][^/\\]+$")
    return here or "."
end)()

-- Where these are allowed: the class library defines them
local ALLOWED = {
    ["script/Core/Structures/Class.lua"] = true,
    ["script/Core/LuaExtensions/TypeEx.lua"] = true,
    ["script/Core/ECS/Registry.lua"] = true,
    ["script/Shared/Save/SaveCodec.lua"] = true, -- asks __type itself: it runs without the class library
    ["tools/code-check.lua"] = true,
}

local RULES = {
    {
        -- At the start of a line: a global assignment (a table field or a
        -- local is indented, or is a local declaration)
        pattern = "^type%s*=[^=]",
        message = "assigns the global `type`: it must stay Lua's own (classOf / isInstance / isPlainTable ask what a value is)",
    },
    {
        pattern = "_G%.type%s*=[^=]",
        message = "assigns the global `type`",
    },
    {
        pattern = "%.isValid%s*[~=]=%s*nil",
        message = "duck-types an entity on its isValid method: use Entity.is",
    },
    {
        pattern = "type%b()%s*[~=]=%s*[\"'][A-Z]",
        message = "compares type(...) with a class name, which is never true: use isInstance / Entity.is",
    },
    {
        pattern = "__type",
        message = "reads __type: use classOf",
    },
}

--- Every .lua file under a directory (git's list when there is one).
local function luaFiles(dir)
    local files = {}
    local p = io.popen(string.format('cd "%s" && git ls-files "%s" 2>/dev/null', repoRoot, dir))
    if p then
        for line in p:lines() do
            if line:match("%.lua$") then files[#files + 1] = line end
        end
        p:close()
    end
    if #files == 0 then
        p = io.popen(string.format('cd "%s" && find "%s" -name "*.lua" 2>/dev/null', repoRoot, dir))
        if p then
            for line in p:lines() do files[#files + 1] = line end
            p:close()
        end
    end
    return files
end

local findings = 0
for _, dir in ipairs({ "script", "tools" }) do
    for _, file in ipairs(luaFiles(dir)) do
        if not ALLOWED[file] and not file:match("^script/jit/") then
            local f = io.open(repoRoot .. "/" .. file, "r")
            if f then
                local n = 0
                for line in f:lines() do
                    n = n + 1
                    -- Comments are not code
                    local code = line:gsub("%-%-.*$", "")
                    for _, rule in ipairs(RULES) do
                        if code:match(rule.pattern) then
                            findings = findings + 1
                            print(string.format("%s:%d: %s", file, n, rule.message))
                            print("    " .. line:gsub("^%s+", ""))
                        end
                    end
                end
                f:close()
            end
        end
    end
end

if findings > 0 then
    print(string.format("%d finding(s)", findings))
    os.exit(1)
end
print("OK")
