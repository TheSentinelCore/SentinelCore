local plugin = {}

plugin["name"] = "SentinelQuester"
plugin["version"] = "0.1.0"
plugin["author"] = "Laidbak"
plugin["load"] = true

-- Do not load while on loading screen / character select.
local local_player = core.object_manager.get_local_player()
if not local_player then
    plugin["load"] = false
    return plugin
end

return plugin
