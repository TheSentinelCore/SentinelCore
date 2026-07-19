local NavigationAdapter = require("modules/grind/vendor_adapters")

local DefaultNavAdapter = {}
DefaultNavAdapter.__index = DefaultNavAdapter

function DefaultNavAdapter:new(nav_adapter)
    local o = setmetatable({}, DefaultNavAdapter)
    o._nav_adapter = nav_adapter
    return o
end

function DefaultNavAdapter:move_to(destination, opts)
    if not self._nav_adapter then return false end
    opts = opts or {}
    self._nav_adapter:move_to(destination, { use_navmesh = opts.use_navmesh ~= false })
    return true
end

function DefaultNavAdapter:stop(reason)
    if not self._nav_adapter then return false end
    self._nav_adapter:stop(reason or "vendor_nav_stop")
    return true
end

function DefaultNavAdapter:is_active()
    if not self._nav_adapter then return false end
    return self._nav_adapter:is_active() == true
end

return DefaultNavAdapter