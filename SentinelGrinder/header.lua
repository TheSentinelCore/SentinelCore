local plugin = {}

local ok, Version = pcall(require, "version")

plugin["name"] = "SentinelGrinder"
plugin["version"] = ok and Version.to_string() or "0.1.0-r1"
plugin["author"] = "Laidbak"
plugin["load"] = true

local local_player = core.object_manager.get_local_player()
if not local_player then
    plugin["load"] = false
    return plugin
end

return plugin
