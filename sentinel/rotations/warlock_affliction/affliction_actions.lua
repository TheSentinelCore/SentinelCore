-- rotations/warlock_affliction/affliction_actions.lua
-- Every cast the Affliction rotation emits.
--
-- ================================================================================
-- WHY THE ONE-LINE WRAPPERS BECAME REAL FUNCTIONS
-- ================================================================================
-- Before the port each action was a partial application of
-- `modules/combat/action_library.lua`'s `cast_target` / `cast_self`:
--
--   Act.cast_corruption = ActionLibrary.cast_target("corruption")
--
-- That require is a cross-package reach the require audit forbids, and `action_library.lua` bottoms
-- out in `shared/combat_helpers.queue_target`, which reaches `module.combat.dispatcher` off the
-- blackboard -- a coupling the require audit cannot see at all, because it travels through a string
-- key rather than an import.
--
-- The two combinators are eight lines of control flow each, so they are inlined here rather than
-- promoted to the kernel surface. What matters is that the INLINE IS FAITHFUL:
--
--   * the `_target` / `_self` action_id suffix survives -- it is the SDK breadcrumb and three
--     existing assertions read it by name;
--   * `cast_target` guards on the TARGET and `cast_self` guards on the PLAYER, and they are
--     different guards. Dropping either changes behaviour when the blackboard is empty;
--   * `combat.target` still wins over `player.target` (via `H.player_and_target`), because the
--     rotation's selection and the client's can diverge and the rotation's is the one that decided.
--
-- ================================================================================
-- WHAT A CAST IS NOW
-- ================================================================================
-- `H.queue_target` emits a `cast` intent under a CASTING lease instead of calling
-- `SpellDispatcher:queue_spell`. SUCCESS therefore means "the intent was accepted for this tick",
-- not "the packet left" -- the packet leaves at COMMIT, if the lease is still live and every gate
-- agrees. See rotations/warlock_affliction/support.lua.
--
-- NO ACTION HERE PASSES `fast` OR `off_gcd`, and that is measured rather than assumed: every
-- Affliction spell in this rotation triggers the global cooldown in TBC. Adding `off_gcd`
-- speculatively would hand a GCD-bound spell a bypass the client will not honour -- the server
-- refuses the packet and the kernel's own report says it went fine.

local H = require("rotations/warlock_affliction/support")

-- Resolved live: `H.status()` reads `Sentinel.bt.Status`, which does not exist until the kernel
-- publishes. Capturing it at load time would pin nil for the whole session.
local Status = setmetatable({}, { __index = function(_, k)
    local s = H.status()
    return s and s[k] or nil
end })

local Act = {}

---Cast at the rotation's current target.
local function cast_target(spell_key)
    return function(blackboard)
        local _, target = H.player_and_target(blackboard)
        if not target then
            return Status.FAILURE
        end
        return H.queue_target(blackboard, spell_key .. "_target", spell_key, target,
            H.QueuePriorities.DEFAULT)
    end
end

---Cast at the player.
local function cast_self(spell_key)
    return function(blackboard)
        local player = blackboard:get("player.object")
        if not player then
            return Status.FAILURE
        end
        return H.queue_target(blackboard, spell_key .. "_self", spell_key, player,
            H.QueuePriorities.DEFAULT)
    end
end

Act.cast_corruption = cast_target("corruption")
Act.cast_curse_of_agony = cast_target("curse_of_agony")
Act.cast_immolate = cast_target("immolate")
Act.cast_drain_life = cast_target("drain_life")
Act.cast_life_tap = cast_self("life_tap")
Act.cast_shadow_bolt = cast_target("shadow_bolt")
Act.cast_shoot = cast_target("shoot")
Act.summon_voidwalker = cast_self("summon_voidwalker")

---Send the Voidwalker at the rotation's target.
---
---A PLAIN FUNCTION, not a factory. `ActionLibrary.pet_attack()` returned a closure and every call
---site invoked the factory inline; the tree now names this directly, matching
---`rotations/mage_frost/frost_actions.lua:507`.
---
---The controller's return value is deliberately IGNORED, exactly as before the port. `attack` now
---answers `(ok, reason, results)` rather than nothing, and letting a refused PET lease turn this
---action FAILURE would change which branch of the off-GCD selector runs. That is a behaviour change
---the port is not authorised to make; the refusal is named in the tick report instead.
function Act.pet_attack(blackboard)
    local pet_ctrl = blackboard:get("module.combat.pet_controller")
    local target = blackboard:get("combat.target") or blackboard:get("player.target")
    if not pet_ctrl or not target then return Status.FAILURE end
    if pet_ctrl:already_sent_to(target) then return Status.FAILURE end
    pet_ctrl:attack(target)
    return Status.SUCCESS
end

function Act.noop()
    return Status.FAILURE
end

return Act
