local providers = {}

local function register(path)
    local ok, provider = pcall(require, path)
    if ok and provider then
        providers[#providers + 1] = provider
    end
end

-- Add new class/spec providers here. RotationEngine consumes this catalog.
register("rotations/paladin/Retribution")

return providers
