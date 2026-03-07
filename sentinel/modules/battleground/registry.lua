local AV = require("modules/battleground/states/av")
local WSG = require("modules/battleground/states/wsg")
local AB = require("modules/battleground/states/ab")
local EOTS = require("modules/battleground/states/eots")

local Registry = {}

function Registry.resolve(bg_key)
    if bg_key == "AV" then
        return AV
    end
    if bg_key == "WSG" then
        return WSG
    end
    if bg_key == "AB" then
        return AB
    end
    if bg_key == "EOTS" then
        return EOTS
    end
    return nil
end

return Registry
