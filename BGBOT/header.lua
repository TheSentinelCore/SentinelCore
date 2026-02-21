-- BGBOT Header
-- Standard Project Sylvanas plugin metadata.
-- BGBOT loads for ALL classes (no class gate — it's a BG bot, not a rotation).

local plugin = {
    name    = "BGBOT",
    author  = "Antigravity",
    version = "0.1.0",
    load    = true,
}

-- Basic safety: ensure core API is available
local me = core.object_manager.get_local_player()
if not me then
    plugin.load = false
end

return plugin
