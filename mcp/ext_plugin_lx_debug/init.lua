------------------------------------------------------------
-- ext_plugin_lx_debug - Live Debug Bridge
-- init.lua - Plugin singleton.
------------------------------------------------------------

---@class LxDebugPlugin
local LxDebugPlugin = {}
LxDebugPlugin.__index = LxDebugPlugin

local _instance = nil

---@return LxDebugPlugin
function LxDebugPlugin:get_instance()
  if _instance then return _instance end
  _instance = setmetatable({}, LxDebugPlugin)
  return _instance
end

return LxDebugPlugin
