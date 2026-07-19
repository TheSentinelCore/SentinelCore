-- sentinel/integrations/sentinel_bridge/event_bridge.lua
-- Event Bridge - Raw-to-semantic translation - ADR 009 §6
-- Translates Sylvanas game events to Sentinel semantic events

local EventBridge = {}

---Translate raw event to semantic event
---@param raw_event string Raw event name from Sylvanas
---@param args table Event arguments
---@return string? semantic_event, table? event_data
function EventBridge.translate_event(raw_event, args)
	local translations = {
		QUEST_LOG_UPDATE = function()
			return nil, { requires_diff = true }
		end,
		BAG_UPDATE = function()
			return "inventory_changed", {}
		end,
		PLAYER_MOVED = function(data)
			return "player_moved", data or {}
		end,
		PLAYER_STARTED_MOVING = function()
			return "player_started_moving", {}
		end,
		PLAYER_STOPPED_MOVING = function(data)
			return "player_stopped_moving", data or {}
		end,
		TAXINODE_LEARNED = function()
			return "flight_learned", {}
		end,
	}

	local fn = translations[raw_event]
	if fn then
		return fn(args)
	end

	return nil, nil
end

---Quest log diffing - identifies what changed between snapshots
---@param old_log table Previous quest log state { quest_id = is_complete }
---@param new_log table Current quest log state { quest_id = is_complete }
---@return table changes { accepted: [], completed: [], abandoned: [] }
function EventBridge.diff_quest_log(old_log, new_log)
	local changes = { accepted = {}, completed = {}, abandoned = {} }

	for quest_id, was_complete in pairs(old_log or {}) do
		local now_complete = new_log[quest_id]
		if not now_complete then
			table.insert(changes.abandoned, quest_id)
		elseif not was_complete and now_complete then
			table.insert(changes.completed, quest_id)
		end
	end

	for quest_id, _ in pairs(new_log or {}) do
		if not old_log or not old_log[quest_id] then
			table.insert(changes.accepted, quest_id)
		end
	end

	return changes
end

---Create a translator instance that wraps event_bus
---@param event_bus table SentinelCore event bus
---@return table Translator instance
function EventBridge.create_translator(event_bus)
	local translator = {
		_event_bus = event_bus,
		_last_quest_log = {},
	}
	setmetatable(translator, { __index = EventBridge })
	return translator
end

---Handle raw event and publish semantic event
---@param raw_event string Raw event name from Sylvanas
---@param args table Event arguments
function EventBridge:handle_event(raw_event, args)
	local semantic, event_data = EventBridge.translate_event(raw_event, args)

	if semantic then
		self._event_bus:publish(semantic, event_data)
	end
end

---Publish quest log change events using diffing
---@param old_log table Previous quest log state
---@param new_log table Current quest log state
function EventBridge:publish_quest_log_changes(old_log, new_log)
	local changes = EventBridge.diff_quest_log(old_log, new_log)

	if self._event_bus then
		for _, qid in ipairs(changes.accepted or {}) do
			self._event_bus:publish("quest_accepted", { quest_id = qid })
		end
		for _, qid in ipairs(changes.completed or {}) do
			self._event_bus:publish("quest_completed", { quest_id = qid })
		end
		for _, qid in ipairs(changes.abandoned or {}) do
			self._event_bus:publish("quest_abandoned", { quest_id = qid })
		end
	end
end

---Poll quest log via AddonsClient and publish semantic events
---@param addons_client table AddonsClient with poll_quest_log method
function EventBridge:poll_and_publish_quest_log(addons_client)
	local current_log = addons_client:poll_quest_log()
	if current_log then
		self:publish_quest_log_changes(self._last_quest_log, current_log)
		self._last_quest_log = current_log
	end
end

---Check if NPC was reached (called by runtime engine)
---@param addons_client table AddonsClient for position/unit queries
---@param npc_guid string Target NPC GUID
---@param arrival_radius number Radius to consider as reached
---@return boolean reached
function EventBridge.check_npc_reached(addons_client, npc_guid, arrival_radius)
	local pos = addons_client.player_position and addons_client:player_position()
	local npc_info = addons_client.unit_info and addons_client:unit_info({ guid = npc_guid })

	if not pos or not npc_info or not npc_info.position then
		return false
	end

	local dx = pos.x - npc_info.position.x
	local dy = pos.y - npc_info.position.y
	local dz = pos.z - npc_info.position.z
	local dist = math.sqrt(dx*dx + dy*dy + dz*dz)

	return dist <= (arrival_radius or 5)
end

return EventBridge