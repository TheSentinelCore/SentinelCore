local plugin = {}

plugin["name"] = "Sentinel Gather"
plugin["version"] = "0.1.0"
plugin["author"] = "Claude"
plugin["load"] = true

-- check if local player exists before loading the script (user is on loading screen / not ingame)
local local_player = core.object_manager.get_local_player()
if not local_player then
    plugin["load"] = false
    return plugin
end

return plugin
