local _aa_helper = nil
local _aa_loaded = false

--- Lazy-load auto_attack_helper singleton.
---@return table|nil
local function get()
    if _aa_loaded then return _aa_helper end
    _aa_loaded = true
    local ok, mod = pcall(require, "common/utility/auto_attack_helper")
    if ok and mod then _aa_helper = mod end
    return _aa_helper
end

return { get = get }
