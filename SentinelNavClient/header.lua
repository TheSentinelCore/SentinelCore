local plugin = {}
plugin["name"] = "NavLib"
plugin["version"] = "0.0.3"
plugin["author"] = "Nasrine"
plugin["load"] = true

local local_player = core.object_manager.get_local_player()
if not local_player or not local_player:is_valid() then
    plugin["load"] = false
    return plugin
end

return plugin