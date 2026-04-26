# https://docs.project-sylvanas.net/dev/libraries/dungeons-helper

Dungeons Helper
Overview​

The Dungeons Helper module provides a comprehensive set of utility functions that aims to make your life easier when trying to gather information about dungeons. Below, we'll explore its functionality.

Importing The Module​

As with all other LUA modules developed by us, you will need to import the Dungeons Helper module into your project. To do so, you can use the following lines:

---@type dungeons_helper

local dungeons_helper = require("common/utility/dungeons_helper")

WARNING

To access the module's functions, you must use : instead of .

For example, this code is not correct:

---@type dungeons_helper

local dungeons_helper = require("common/utility/dungeons_helper")



local function check_if_player(unit)

    return dungeons_helper.is_mythic_dungeon(unit)

end


And this would be the corrected code:

---@type inventory_helper

local dungeons_helper = require("common/utility/dungeons_helper")



local function is_player_in_mythic_dungeon()

    return dungeons_helper:is_mythic_dungeon()

end

Functions​
is_mythic_dungeon() -> boolean​

Returns true if the local player is currently in a Mythic dungeon.

Returns:
boolean -> True if the local player is currently in a Mythic dungeon, false otherwise.
get_mythic_key_level() -> integer​

Retrieves the key level of the current Mythic dungeon.

Returns:
key level integer: The key level of the current Mythic dungeon.
is_kite_exception() -> boolean​

Checks if we are on kite exception.

Returns:
boolean: If we are on kite exception.
game_object | nil:
game_object | nil:
is_kikatal_near_cosmic_cast(energy_threshold: number) -> boolean​

Checks if kikatal is near a cosmic cast within a given energy threshold.

Returns:
boolean: If Kikatal is near cosmic cast.
game_object | nil:
is_kikatal_grasping_blood_exception() -> boolean, game_object | nil, game_object | nil​

Checks if we are under a kikatal grasping blood exception.

Returns:
boolean: If Kikatal is near cosmic cast.
game_object | nil:
game_object | nil: