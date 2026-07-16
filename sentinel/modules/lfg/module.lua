local Settings = require("modules/lfg/settings")

local Lfg = {}
Lfg.__index = Lfg

function Lfg.new(event_bus, blackboard)
    return setmetatable({
        _event_bus = event_bus,
        _blackboard = blackboard,
        _subscriptions = {},
        _enabled = Settings.enabled == true,
        _last_search_ms = 0,
        _pending_result_id = nil,
    }, Lfg)
end

function Lfg:initialize()
    self._blackboard:set("module.lfg.enabled", self._enabled)
    self._blackboard:set("module.lfg.state", "IDLE")

    self._subscriptions[#self._subscriptions + 1] = self._event_bus:subscribe(
        "game:lfg_search_result_updated",
        function()
            self:_evaluate_results()
        end
    )
    self._subscriptions[#self._subscriptions + 1] = self._event_bus:subscribe(
        "game:lfg_application_status_updated",
        function()
            self:_publish_application_state()
        end
    )
end

function Lfg:update(blackboard)
    if not self._enabled or not core or not core.lfg_list then
        return
    end
    local now_ms = blackboard:get("system.now_ms", 0)
    if now_ms - self._last_search_ms < Settings.search_interval_ms then
        return
    end
    self._last_search_ms = now_ms
    self:search()
end

function Lfg:search()
    if not core or not core.lfg_list or Settings.category_id <= 0 then
        return false
    end
    local ok, issued = pcall(
        core.lfg_list.search,
        Settings.category_id,
        Settings.filter,
        Settings.preferred_filters
    )
    if not ok or issued ~= true then
        self._blackboard:set("module.lfg.state", "SEARCH_SKIPPED")
        return false
    end
    self._blackboard:set("module.lfg.state", "SEARCHING")
    return true
end

function Lfg:_evaluate_results()
    if not core or not core.lfg_list then
        return
    end
    local ok, results = pcall(core.lfg_list.get_search_results)
    if not ok or type(results) ~= "table" then
        return
    end
    for _, result_id in ipairs(results.result_ids or {}) do
        local has_info = core.lfg_list.has_search_result_info(result_id)
        if has_info then
            local info = core.lfg_list.get_search_result_info(result_id)
            local counts = core.lfg_list.get_search_result_member_counts(result_id)
            if info and not info.is_delisted and counts then
                local available = Settings.role == "tank" and counts.tank_remaining
                    or Settings.role == "healer" and counts.healer_remaining
                    or counts.damager_remaining
                if (available or 0) > 0 then
                    local applied, err = core.lfg_list.apply_to_group(
                        result_id,
                        Settings.role == "tank",
                        Settings.role == "healer",
                        Settings.role == "damage"
                    )
                    if applied then
                        self._pending_result_id = result_id
                        self._blackboard:set("module.lfg.state", "APPLIED")
                    else
                        self._blackboard:set("module.lfg.last_error", tostring(err))
                    end
                    return
                end
            end
        end
    end
end

function Lfg:_publish_application_state()
    if not self._pending_result_id or not core or not core.lfg_list then
        return
    end
    local info = core.lfg_list.get_application_info(self._pending_result_id)
    if not info then
        return
    end
    self._blackboard:set("module.lfg.application_status", info.app_status)
    if Settings.auto_accept_invite and info.app_status == "invited" then
        local ok, err = core.lfg_list.accept_invite(self._pending_result_id)
        if ok then
            self._blackboard:set("module.lfg.state", "INVITE_ACCEPTED")
        else
            self._blackboard:set("module.lfg.last_error", tostring(err))
        end
    end
end

function Lfg:set_enabled(enabled)
    self._enabled = enabled == true
    self._blackboard:set("module.lfg.enabled", self._enabled)
end

function Lfg:shutdown()
    for _, token in ipairs(self._subscriptions) do
        self._event_bus:unsubscribe(token)
    end
    self._subscriptions = {}
end

return Lfg
