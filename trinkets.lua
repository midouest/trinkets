-- flexible midi-to-crow routing
local fennel = include("lib/fennel")
debug.traceback = fennel.traceback

local allowedGlobals = {"includelua", "includefnl"}
for k, _ in pairs(_G) do table.insert(allowedGlobals, k) end

includelua = include

function includefnl(file)
    local dirs = {norns.state.path, _path.code, _path.extn}
    for _, dir in ipairs(dirs) do
        local p = dir .. file .. '.fnl'
        if util.file_exists(p) then
            print("including " .. p)
            return fennel.dofile(p, {allowedGlobals = allowedGlobals})
        end
    end

    -- didn't find anything
    print("### MISSING INCLUDE: " .. file)
    error("MISSING INCLUDE: " .. file, 2)
end

local app = includefnl("lib/app")

init = app.init
cleanup = app.cleanup
redraw = app.redraw
enc = app.enc
key = app.key
