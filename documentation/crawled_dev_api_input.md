# https://docs.project-sylvanas.net/dev/api/input

Input Functions and Spell Queue
Overview 📃​

In this module we introduce one of the most (if not the most) important features for scripting: a way to manage input from code. For now, this only includes spell casting. However, stay tuned to the changelogs, since other input methods like movement are planned to be supported in the near future.

The Way Raw Input Functions Work

Similar to what we previously discussed in the buffs page, the raw input functions that the game provides to us have some disadvantages. In this case, they are not FPS-related, but rather usability and safety related. These functions basically send a paquet to the game's server that mimics a legit spell cast or movement. Therefore, spamming raw inputs from code may be dangerous since you might be sending many more requests per seconds than any human would be able to send. So far, this is not a problem for us, but it's something to take into account for the future, as Blizzard anticheat evolves.

The real problem is usability 💥:
1 - Compatibility between plugins: If your scripts spam input requests, you will make everything else useless. For example, other modules like "Core Interrupt" might want to cast a spell to interrupt an important enemy cast. This usually has more priority than the normal damage rotation, but since you are flooding the server with your requests, the interruptor spell cast request won't have a chance to be sent.
2 - User Experience: If your script spam input requests you make the user unable to cast their own spells manually. As you could imagine, there might me certain situations in which the users have to cast certain spells on their own, so blocking this could be very frustrating them. To fix this, we handle everything in our LUA Spell Queue Module, which will be explained in detail below.

WARNING

You can still use raw input functions, but at your own risk. We advise you to read thoroughly the previous explanation and check if you really really need to use the raw functions. If you have any question, contact us and we will guide you through without any problem - Better safe than sorry. ❤️

NOTE

For some items that don't have global cooldown, the raw "Use Item" functions are perfectly fine, just make sure to add checks before the cast so you don't spam when the item isn't ready.

Raw Input Functions 📃​
Cast Target Spell 💣​

core.input.cast_target_spell(spell_id: integer, target: game_object) -> boolean

Cast a spell directly at a target.
Parameters:
spell_id: The ID of your chosen spell
target: The game_object that you want to cast the spell to
Returns: true if the spell was cast, false if it fizzled
NOTE

This function JUST sends a cast request to the server. It doesn't check if the enemy is close enough, if you are facing it, if the spell is ready, etc. Therefore, you must apply all these checks before casting. To do so, we created a LUA Spell Helper module that will make the job very easy. Check spell book.

We advise you to check the Spell Book module before jumping into input code. This is the proper way you should be casting spells:

---@type spell_helper

local spell_helper = require("common/utility/spell_helper")



---@type plugin_helper

local plugin_helper = require("common/utility/plugin_helper")



local last_cast_time = 0.0

core.register_on_update_callback(function()

    -- if we remove this check, you will see in the console that more than 1 cast request is issued.

    -- To avoid this and only send one (this is good practice behaviour), we add a minimum delay of 0.25 seconds

    -- for this function to be ran again.

    local current_time = core.game_time()

    if current_time - last_cast_time < 0.50 then

        return false

    end



    local local_player = core.object_manager.get_local_player()

    if not local_player then

        return

    end



    -- since this is just a test, we will just get the hud target

    local hud_target = local_player:get_target()

    -- only cast the fireball when there is a target selected

    if not hud_target then

        return

    end



    -- avoid spamming cast request while already casting

    -- NOTE: in your scripts, you might want to do the same for channels.



    -- approach 1: take into account network latency



    -- local network = plugin_helper:get_latency()

    -- local cast_end_time = local_player:get_active_spell_cast_end_time()

    -- local cast_delta = math.max(cast_end_time - current_time, 0.0)

    -- if cast_delta > (network * 1000) then

    --     return

    -- end



    -- approach 2: more simple, works well in most cases.

    local cast_end_time = local_player:get_active_spell_cast_end_time()

    if current_time <= cast_end_time then

        return

    end



    local fireball_id = 133



    -- check first if the spell is castable, so we avoid sending useless packets (the script will be stuck permanently trying to cast a spell that can't be casted)

    local can_cast_fireball = spell_helper:is_spell_castable(fireball_id, local_player, hud_target, false, false)

    if not can_cast_fireball then

        return

    end



    local spell_cast = core.input.cast_target_spell(fireball_id, hud_target)

    if spell_cast then

        core.log("Fireball Cast!")

        last_cast_time = current_time

    end

end)


This example might be an overkill, specially if you are a beginner and are learning. Feel free to play with the code and go step by step. However, if you want to produce good quality products, consider adding at least all the steps specified in the previous example to your casts.

Cast Position Spell 💣​

core.input.cast_position_spell(spell_id: integer, position: vec3) -> boolean

Cast a spell at a specific location in the world.
Parameters:
spell_id: Your spell's ID
position: The XYZ coordinates for your spell. See vec3
Returns: true if cast successfully, false if not
NOTE

This function is only used for spells that don't require a target game_object, but instead require a target position. This is usually the case for some AOE spells like Blizzard or Flamestrike.

Let's cast a Flamestrike:

---@type spell_helper

local spell_helper = require("common/utility/spell_helper")



---@type plugin_helper

local plugin_helper = require("common/utility/plugin_helper")



local last_cast_time = 0.0

core.register_on_update_callback(function()

    -- if we remove this check, you will see in the console that more than 1 cast request is issued.

    -- To avoid this and only send one (this is good practice behaviour), we add a minimum delay of 0.25 seconds

    -- for this function to be ran again.

    local current_time = core.game_time()

    if current_time - last_cast_time < 0.50 then

        return false

    end



    local local_player = core.object_manager.get_local_player()

    if not local_player then

        return

    end



    -- since this is just a test, we will just get the hud target

    local hud_target = local_player:get_target()

    -- only cast the fireball when there is a target selected

    if not hud_target then

        return

    end



    -- avoid spamming cast request while already casting

    -- NOTE: in your scripts, you might want to do the same for channels.



    -- approach 1: take into account network latency



    -- local network = plugin_helper:get_latency()

    -- local cast_end_time = local_player:get_active_spell_cast_end_time()

    -- local cast_delta = math.max(cast_end_time - current_time, 0.0)

    -- if cast_delta > (network * 1000) then

    --     return

    -- end



    -- approach 2: more simple, works well in most cases.

    local cast_end_time = local_player:get_active_spell_cast_end_time()

    if current_time <= cast_end_time then

        return

    end



    local flamestrike_id = 2120



    -- check first if the spell is castable, so we avoid sending useless packets (the script will be stuck permanently trying to cast a spell that can't be casted)

    local can_cast_fireball = spell_helper:is_spell_castable(flamestrike_id, local_player, hud_target, false, false)

    if not can_cast_fireball then

        return

    end



    local position_to_cast = hud_target:get_position()

    local spell_cast = core.input.cast_position_spell(flamestrike_id, position_to_cast)

    if spell_cast then

        core.log("Flamestrike Cast On Target Position!")

        last_cast_time = current_time

    end

end)

TIP

As you can see, in the previous example we are casting the spell to the target's position, without any further checks. For AOE spells, you would ideally want to cast on the position that would hit the most enemies, which is usually not the same as your main target's position. To do this, you should use some sort of algorithm to determine which is the actual best point to cast, according to your spell's characteristics. To do this, we have developed the "Spell Prediction" module. See Spell Prediction Module

Use Item 🎭​

We have three item usage functions, each with its own purpose:


1- Item Self-Cast
core.input.use_item(item_id: integer) -> boolean

This function is used for items that don't require a target or a target position.

2- Item Targeted-Cast
core.input.use_item_target(item_id: integer, target: game_object) -> boolean

This function is used for items that require a target or a target position.

3- Item Position-Cast
core.input.use_item_position(item_id: integer, position: vec3) -> boolean

Use an item at a specific location. (Note: This feature is still in development)
TIP

Most items don't have a global cooldown, so these raw functions are usually fine, as we discussed earlier. However, for items that apply GCD, consider using the spell_queue.

The code for casting items is pretty similar to the code for casting spells. You just have to be careful with the way you check if the item is ready, since it's different from checking if a spell is ready. Below, a simple example on how to cast a health potion:

---@type unit_helper

local unit_helper = require("common/utility/unit_helper")



local last_cast_time = 0.0

core.register_on_update_callback(function()

    -- if we remove this check, you will see in the console that more than 1 cast request is issued.

    -- To avoid this and only send one (this is good practice behaviour), we add a minimum delay of 0.25 seconds

    -- for this function to be ran again.

    local current_time = core.game_time()

    if current_time - last_cast_time < 5.0 then

        return false

    end



    local local_player = core.object_manager.get_local_player()

    if not local_player then

        return

    end



    local cast_end_time = local_player:get_active_spell_cast_end_time()

    if current_time <= cast_end_time then

        return

    end



    -- the potion for this example is the "Greater Healing Potion"

    local potion_id = 1710

    local item_cooldown = local_player:get_item_cooldown(potion_id)

    local can_cast_potion = item_cooldown <= 0.0

    if not can_cast_potion then

        return false

    end



    -- we add this check so the potion is not attempted to be cast while full HP, since the game won't allow it.

    if unit_helper:get_health_percentage(local_player) >= 1.0 then

        return false

    end



    local spell_cast = core.input.use_item(potion_id)

    if spell_cast then

        core.log("Potion cast!")

        last_cast_time = current_time

    end

end)

Set Target 🎯​

core.input.set_target(unit: game_object) -> boolean

Set your current target.
Returns: true if targeting was successful, false if not

Example:

local local_player = core.object_manager.get_local_player()

if local_player then

    local player_position = local_player:get_position()

    local nearby_enemies = unit_helper:get_enemy_list_around(player_position, 30)



    for _, unit in ipairs(nearby_enemies) do

        local success = core.input.set_target(unit)

        if success then

            core.log("New target acquired! 🎯")

            break

        else

            core.log("Targeting failed. They're quick! 💨")

        end

    end

end

Set and Get Focus 🔍​
core.input.set_focus(unit: game_object) -> boolean: Set your focus target
core.input.get_focus() -> game_object | nil: Retrieve your current focus

Checking your focus:

local current_focus = core.input.get_focus()

if current_focus then

    core.log("Current focus: " .. current_focus:get_name() .. " 🔍")

else

    core.log("No focus set currently")

end

Spell Queue Module: Advanced Spell Management 🧠​

As discussed earlier, spell_queue module offers sophisticated spell management with priority queuing. It's the go-to tool for complex spell rotations and efficient casting, and what you should be using in most cases.


The Way The Spell Queue Module Works
Basically, this module just implements a priority queue for spell casts. When you send a spell cast request, it's added into the queue with a priority value that's passed by parameter. The queue is sorted every frame according to the priority values of the elements inside the said data structure. This way, we can make sure that the most important spells are casted before the less important ones, and we also secure compatibility between plugins, as any plugin can send a cast request at any given time.

Importing the Module​
---@type spell_queue

local spell_queue = require("common/modules/spell_queue")

WARNING

Remember to use the colon (:) when calling spell_queue methods!

Queue Spell with Target 🎯​

spell_queue:queue_spell_target(spell_id: number, target: game_object, priority: number, message?: string)

Queue a targeted spell with priority.
priority: Higher numbers = higher priority (1 is default, 9 is highest)
message: Optional logging message

Queueing a Fireball:

---@type spell_helper

local spell_helper = require("common/utility/spell_helper")



---@type plugin_helper

local plugin_helper = require("common/utility/plugin_helper")



---@type spell_queue

local spell_queue = require("common/modules/spell_queue")



local last_cast_time = 0.0

core.register_on_update_callback(function()

    -- if we remove this check, you will see in the console that more than 1 cast request is issued.

    -- To avoid this and only send one (this is good practice behaviour), we add a minimum delay of 0.25 seconds

    -- for this function to be ran again.

    local current_time = core.game_time()

    if current_time - last_cast_time < 0.50 then

        return false

    end



    local local_player = core.object_manager.get_local_player()

    if not local_player then

        return

    end



    -- since this is just a test, we will just get the hud target

    local hud_target = local_player:get_target()

    -- only cast the fireball when there is a target selected

    if not hud_target then

        return

    end



    -- avoid spamming cast request while already casting

    -- NOTE: in your scripts, you might want to do the same for channels.



    -- approach 1: take into account network latency



    -- local network = plugin_helper:get_latency()

    -- local cast_end_time = local_player:get_active_spell_cast_end_time()

    -- local cast_delta = math.max(cast_end_time - current_time, 0.0)

    -- if cast_delta > (network * 1000) then

    --     return

    -- end



    -- approach 2: more simple, works well in most cases.

    local cast_end_time = local_player:get_active_spell_cast_end_time()

    if current_time <= cast_end_time then

        return

    end



    local fireball_id = 133



    -- check first if the spell is castable, so we avoid sending useless packets (the script will be stuck permanently trying to cast a spell that can't be casted)

    local can_cast_fireball = spell_helper:is_spell_castable(fireball_id, local_player, hud_target, false, false)

    if not can_cast_fireball then

        return

    end



    spell_queue:queue_spell_target(fireball_id, hud_target, 1, "Trying to cast fireball!")

    last_cast_time = current_time

end)


As you can see, the code is pretty much the same as the code that we would use for raw functions, the only thing that changes is the way we are attempting to cast the spell.

Queue Fast Spell with Target 🎯​

spell_queue:queue_spell_target_fast(spell_id: number, target: game_object, priority: number, message?: string)

The code would be exactly the same as the previous example, you just need to replace the queue spell function call.

Queue Spell with Position 🎯​

spell_queue:queue_spell_position(spell_id: number, position: vec3, priority: number, message?: string)

Queue a position-based spell.

As you can imagine, the code to cast Flamestrike using spell queue is pretty much the same as the code we used to cast Flamestrike with raw spells, the only thing that changes is the way we are issuing the actual cast. So, maybe it's more interesting to use the spell prediction for a smart Blizzard cast for this example:

local local_player = core.object_manager.get_local_player()

if local_player then

    local hud_target = local_player:get_target()

    if hud_target then

        local blizzard_id = 10

        local player_position = local_player:get_position()

        local prediction_spell_data = spell_prediction:new_spell_data(

            blizzard_id,                                    -- spell_id

            30,                                             -- range

            6,                                              -- radius

            0.2,                                            -- cast_time

            0.0,                                            -- projectile_speed

            spell_prediction.prediction_type.MOST_HITS,     -- prediction_type

            spell_prediction.geometry_type.CIRCLE,          -- geometry_type

            player_position                                 -- source_position

        )



        local prediction_result = spell_prediction:get_cast_position(hud_target, prediction_spell_data)

        if prediction_result and prediction_result.amount_of_hits > 0 then

            spell_queue:queue_spell_position(blizzard_id, prediction_result.cast_position, 1, "Queueing Blizzard at optimal position")

        end

    end

end


This code:

Sets up a Blizzard spell with prediction data
Uses MOST_HITS prediction type to maximize the spell's impact
Queues the Blizzard at the optimal position if targets are predicted to be hit

NOTE

As you can see, we call prediction_type.MOST_HITS to fire Death and Decay on the Priest. Instead of casting on the center, it strategically places the spell slightly to the left to hit extra dummies aswell.

TIP

Test with the prediction_type.ACCURACY values for pinpointing situations where the cast should be avoided

Queue Fast Spell with Position 🎯​

spell_queue:queue_spell_position_fast(spell_id: number, position: vec3, priority: number, message?: string)

Queue a position-based spell that ignores the global cooldown.

The code would be exactly the same as the previous example, you just need to replace the queue spell function call

Best Practices 🧙‍♂️💡​
1- Embrace the Spell Queue

2- Remember the priority scale (1-9). Use it to create sophisticated casting logic.


WARNING

Be cautious with priority levels! While 1 is the default, higher priorities should be applied only when absolutely necessary.

1 is the default priority, intended for the majority of spells in the standard rotation. Developers should strive to keep spells at priority 1 unless a clear, specific reason justifies using a higher priority. This preserves rotation efficiency and prevents disruption.

Higher priorities are intended for spells that require urgent action outside the rotation. For example, interrupts use priority 7 to ensure they execute immediately when conditions demand it, as timing is crucial for effective interruption. Core utility spells, such as racials, dispels, or spell reflections, are typically set between 4 to 6. They preempt the rotation without overshadowing interrupts, allowing critical utilities to occur in time-sensitive situations.

Finally, priority 9 is exclusively reserved for manual player actions, ensuring that the player’s chosen spell overrides any automated rotation or interrupt, with no delay.

In short, unless there is a compelling plan, stick with priority 1 for your spells. Use 2 only if you have a strong plan.

3- Fast Track Important Spells

Use _fast versions for critical, non-GCD spells.

4- Leave Breadcrumbs

Use the message parameter in spell_queue for easier debugging.

5- Learn to Use The Prediction Module

The spell_prediction module is powerful and easy to use library to evolve your logics.

Remember, mastering these tools takes practice. Experiment with different combinations and priorities to find what works best for your scripting needs.

More Raw Input Functions​
Movement Controls 🎮​
move_up_start()​

Starts moving the player upwards (used in flying scenarios).

Returns: boolean — true if the movement command was issued successfully.

move_up_stop()​

Stops the upward movement.

Returns: boolean — true if the movement command was issued successfully.

move_down_start()​

Starts moving the player downwards (used in flying or swimming scenarios).

Returns: boolean — true if the movement command was issued successfully.

move_down_stop()​

Stops the downward movement.

Returns: boolean — true if the movement command was issued successfully.

jump()​

Makes the player jump.

Returns: boolean — true if the jump command was issued successfully.

Mounting and Dismounting 🐎​
mount()​

Mounts the player's active mount.

Returns: boolean — true if the mount command was issued successfully.

dismount()​

Dismounts the player from their mount.

Returns: boolean — true if the dismount command was issued successfully.

Resurrection and Spirit Release 🎭​
release_spirit()​

Releases the player's spirit after death.

Returns: boolean — true if the spirit release command was issued successfully.

resurrect_corpse()​

Resurrects the player’s corpse.

Returns: boolean — true if the resurrection command was issued successfully.

Expanded Movement Controls 🎮​
move_forward_start()​

Starts moving the player forward.

move_forward_stop()​

Stops forward movement.

move_backward_start()​

Starts moving the player backward.

move_backward_stop()​

Stops backward movement.

turn_right_start()​

Starts turning the player to the right.

turn_right_stop()​

Stops turning to the right.

turn_left_start()​

Starts turning the player to the left.

turn_left_stop()​

Stops turning to the left.

Pet Control Functions 🐾​
pet_move(position: vec3)​

Commands the pet to move to the specified position.

pet_attack(target: game_object)​

Commands the pet to attack the target.

set_pet_wait()​

Sets the pet to wait at its current position.

set_pet_follow()​

Commands the pet to follow the player.

set_pet_assist()​

Sets the pet to assist the player.

set_pet_passive()​

Sets the pet to passive mode.

set_pet_defensive()​

Sets the pet to defensive mode.

set_pet_aggressive()​

Sets the pet to aggressive mode.

pet_move_position(position: vec3)​

Moves the pet to a specified world position.

pet_cast_target_spell(spell_id: integer, target: game_object)​

Commands the pet to cast a spell on a target.

pet_cast_position_spell(spell_id: integer, position: vec3)​

Commands the pet to cast a spell at a specific position.

Loot and Combat Management 🧹​
loot_object(unit: game_object)​

Loots the specified object.

stop_attack()​

Stops all ongoing player attacks.

Returns: boolean — true if the stop command was issued successfully.