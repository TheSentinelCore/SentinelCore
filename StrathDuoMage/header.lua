local plugin = {}
plugin["name"] = "StrathDuoMage"
plugin["version"] = "0.1.0"
plugin["author"] = "Codex"
plugin["load"] = true

local local_player = core and core.object_manager and core.object_manager.get_local_player and core.object_manager.get_local_player()
if not local_player or (local_player.is_valid and not local_player:is_valid()) then
    plugin["load"] = false
    return plugin
end

return plugin
