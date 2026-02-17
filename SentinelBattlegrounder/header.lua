local plugin = {}
local VERSION = require("version")

plugin["name"] = "SentinelBattlegrounder"
plugin["version"] = VERSION
plugin["author"] = "Laidbak83"
plugin["load"] = true

local local_player = core.object_manager.get_local_player()
if not local_player then
    plugin["load"] = false
    return plugin
end

return plugin
