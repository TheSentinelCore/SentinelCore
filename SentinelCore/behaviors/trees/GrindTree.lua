local CombatKernelTree = require("behaviors/trees/CombatKernelTree")

local GrindTree = {}

---@param services table
---@param command_handlers table
---@return table
function GrindTree.create(services, command_handlers)
    return CombatKernelTree.create(services, command_handlers)
end

return GrindTree
