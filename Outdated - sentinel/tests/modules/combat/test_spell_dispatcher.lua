local Blackboard = require("core/blackboard")
local EventBus = require("core/event_bus")
local SpellDispatcher = require("modules/combat/spell_dispatcher")
local T = require("tests/test_util")

local M = {}

local function make_target(guid)
    return {
        get_guid = function()
            return guid
        end,
    }
end

function M.run()
    local bb = Blackboard:new()
    local bus = EventBus:new()
    local dispatcher = SpellDispatcher:new(bus, bb)
    local target = make_target("enemy")

    bb:set("system.now_ms", 1000)

    spell_queue = {
        _snapshot = {},
        queue_spell_target = function(self, spell_id, passed_target, priority)
            if self._append_on_queue then
                self._snapshot[#self._snapshot + 1] = {
                    spell_id = spell_id,
                    priority = priority,
                    target = passed_target,
                    timestamp = 1234 + #self._snapshot,
                }
            end
        end,
        get_queue_snapshot = function(self)
            return self._snapshot
        end,
    }

    local ok = dispatcher:queue_target("judgement", 20271, target, 3, "judgement", {})
    T.assert_false(ok, "dispatcher should reject a queue call that never appears in snapshot")
    T.assert_equal(bb:get("rotation.last_block_reason"), "queue_not_observed_in_snapshot")

    spell_queue._append_on_queue = true
    bb:set("system.now_ms", 2000)
    ok = dispatcher:queue_target("judgement_retry", 20271, target, 3, "judgement_retry", {})
    T.assert_true(ok, "dispatcher should accept a queue call once snapshot shows the spell")
    T.assert_equal(bb:get("rotation.last_action_id"), "judgement_retry")

    local target_two = make_target("enemy-two")
    bb:set("system.now_ms", 2050)
    ok = dispatcher:queue_target("judgement_retry", 20271, target_two, 3, "judgement_retry", {})
    T.assert_true(ok, "dispatcher should allow the same spell/action inside the dedupe window when target changes")
    T.assert_equal(bb:get("rotation.last_queue_target_guid"), "enemy-two")
end

return M
