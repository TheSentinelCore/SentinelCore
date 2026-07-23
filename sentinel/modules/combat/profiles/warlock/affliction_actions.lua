local ActionLibrary = require("modules/combat/action_library")
local Status = require("core/bt/status")

-- Thin wrappers over ActionLibrary.cast_target/cast_self -- no bespoke queueing
-- logic needed for the Affliction leveling MVP (mirrors the reuse-first pattern
-- already established: paladin/mage Act modules only add bespoke logic where
-- the generic library isn't enough, e.g. rotation.twist bookkeeping).
local Act = {}

Act.cast_corruption = ActionLibrary.cast_target("corruption")
Act.cast_curse_of_agony = ActionLibrary.cast_target("curse_of_agony")
Act.cast_immolate = ActionLibrary.cast_target("immolate")
Act.cast_drain_life = ActionLibrary.cast_target("drain_life")
Act.cast_life_tap = ActionLibrary.cast_self("life_tap")
Act.cast_shadow_bolt = ActionLibrary.cast_target("shadow_bolt")
Act.cast_shoot = ActionLibrary.cast_target("shoot")
Act.summon_voidwalker = ActionLibrary.cast_self("summon_voidwalker")

function Act.noop()
    return Status.FAILURE
end

return Act
