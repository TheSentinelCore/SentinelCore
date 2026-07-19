-- sentinel/integrations/sentinel_bridge/bridge_error.lua
-- BridgeError types - ADR 009 §10
-- Error types for Sylvanas bridge layer

local BridgeError = {}

BridgeError.ApiUnavailable = {
    code = "API_UNAVAILABLE",
    message = "Sylvanas API is not available or not responding",
    fatal = true,
}

BridgeError.NpcNotFound = {
    code = "NPC_NOT_FOUND",
    message = "NPC not found or no longer valid",
    fatal = false,
}

BridgeError.QuestNotFound = {
    code = "QUEST_NOT_FOUND",
    message = "Quest not found in quest log",
    fatal = false,
}

BridgeError.InteractionOutOfRange = {
    code = "INTERACTION_OUT_OF_RANGE",
    message = "NPC is not in interaction range",
    fatal = false,
}

BridgeError.Timeout = {
    code = "TIMEOUT",
    message = "Operation timed out waiting for response",
    fatal = false,
}

BridgeError.UnexpectedGameState = {
    code = "UNEXPECTED_GAME_STATE",
    message = "Game is in an unexpected state",
    fatal = false,
}

function BridgeError.new(code, message, fatal)
    return {
        code = code,
        message = message,
        fatal = fatal,
    }
end

function BridgeError.api_unavailable()
    return BridgeError.new("API_UNAVAILABLE", "Sylvanas API is not available or not responding", true)
end

function BridgeError.npc_not_found(npc_guid)
    return BridgeError.new("NPC_NOT_FOUND", "NPC not found: " .. tostring(npc_guid), false)
end

function BridgeError.quest_not_found(quest_id)
    return BridgeError.new("QUEST_NOT_FOUND", "Quest not found: " .. tostring(quest_id), false)
end

function BridgeError.interaction_out_of_range(npc_guid)
    return BridgeError.new("INTERACTION_OUT_OF_RANGE", "NPC out of range: " .. tostring(npc_guid), false)
end

function BridgeError.timeout(operation)
    return BridgeError.new("TIMEOUT", "Operation timed out: " .. tostring(operation), false)
end

function BridgeError.unexpected_game_state(state)
    return BridgeError.new("UNEXPECTED_GAME_STATE", "Unexpected game state: " .. tostring(state), false)
end

function BridgeError.is_fatal(err)
    if type(err) == "table" then
        return err.fatal == true
    end
    return false
end

function BridgeError.format(err)
    if type(err) == "table" then
        return err.code .. ": " .. err.message
    end
    return tostring(err)
end

return BridgeError