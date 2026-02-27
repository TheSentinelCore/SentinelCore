local VendorService = {}
VendorService.__index = VendorService

---@class VendorService
function VendorService:new(bb, cfg, logger)
    local o = setmetatable({}, VendorService)
    o._bb = bb
    o._cfg = cfg or {}
    o._log = logger
    return o
end

function VendorService:_resolve_free_slots()
    if core and core.inventory and type(core.inventory.get_free_slots) == "function" then
        local ok, slots = pcall(core.inventory.get_free_slots)
        if ok and tonumber(slots) then
            return tonumber(slots)
        end
    end

    if core and core.inventory and type(core.inventory.get_total_free_bag_slots) == "function" then
        local ok, slots = pcall(core.inventory.get_total_free_bag_slots)
        if ok and tonumber(slots) then
            return tonumber(slots)
        end
    end

    return nil
end

function VendorService:update()
    if self._cfg.farm and self._cfg.farm.enable_vendor == false then
        self._bb:set("vendor.needs_trip", false)
        return
    end

    local free_slots = self:_resolve_free_slots()
    if free_slots == nil then
        return
    end

    self._bb:set("inventory.free_slots", free_slots)
    local min_free = tonumber(self._cfg.farm and self._cfg.farm.min_free_slots) or 2
    self._bb:set("vendor.needs_trip", free_slots <= min_free)
end

return VendorService
