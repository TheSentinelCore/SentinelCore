# https://docs.project-sylvanas.net/dev/api/geometry

Geometry
Overview​

The geometry module provides a set of classes to create and interact with geometric shapes such as circles, rectangles, and cones. These classes offer various methods to manipulate the shapes, check points within them, retrieve units inside them, and visualize them by drawing.

TIP

These classes are helpful for area-of-effect calculations, targeting systems, and visual debugging.

WARNING

This is a Lua library stored inside the "common" folder. To use it, you will need to include the library. Use the require function and store it in a local variable.

Here is an example of how to do it:

-- Recommended "circle" name for consistency

local circle = require("common/geometry/circle")



local cursor_position = core.get_cursor_position()

local my_circle = circle:create(cursor_position, 5.0)

Classes​
Circle​

The circle class represents a circle with a center point and a radius.

Properties​
center: vec3 — The center position of the circle.
radius: number — The radius of the circle.
Methods​
create(center, radius)​

Creates a circle given a center and radius.

Parameters:
center (vec3) — The center position of the circle.
radius (number) — The radius of the circle.

Returns: circle — A new circle instance.

is_inside(point, hitbox)​

Checks if a point is inside the circle.

Parameters:
point (vec3) — The point to check.
hitbox (number) — The hitbox radius to consider.

Returns: boolean — true if the point is inside; otherwise, false.

get_units_inside(units_list)​

Retrieves units within the circle.

Parameters:
units_list (table<game_object>, optional) — List of units to check. If not provided, retrieves all units around the circle's center.

Returns: table<game_object> — A table of units inside the circle.

get_allies_inside(units_list_override)​

Retrieves allies within the circle.

Parameters:
units_list_override (table<game_object>, optional) — List of units to check. If not provided, retrieves all units around the circle's center.

Returns: table<game_object> — A table of allies inside the circle.

get_enemies_inside(units_list_override)​

Retrieves enemies within the circle.

Parameters:
units_list_override (table<game_object>, optional) — List of units to check. If not provided, retrieves all units around the circle's center.

Returns: table<game_object> — A table of enemies inside the circle.

draw(custom_height)​

Draws the circle.

Parameters:
custom_height (number, optional) — Custom height to draw the circle.

Returns: nil

draw_with_counter(count)​

Draws the circle and the number of units hit.

Parameters:
count (number, optional) — Number of units hit. If not provided, calculates the number of units inside the circle.

Returns: nil

Rectangle​

The rectangle class represents a rectangle with four corners, a width, and a length.

Properties​
corner1: vec3 — The first corner of the rectangle.
corner2: vec3 — The second corner of the rectangle.
corner3: vec3 — The third corner of the rectangle.
corner4: vec3 — The fourth corner of the rectangle.
width: number — The width of the rectangle.
length: number — The length of the rectangle.
origin: vec3 — The origin position of the rectangle.
Methods​
create(origin, destination, width, length)​

Creates a rectangle given an origin, destination, width, and length.

Parameters:
origin (vec3) — The origin position.
destination (vec3) — The destination position.
width (number) — The width of the rectangle.
length (number, optional) — The length of the rectangle. If not provided, it is calculated from the origin and destination.

Returns: rectangle — A new rectangle instance.

create_direction(position, direction, width, length)​

Creates a rectangle given a position, direction, width, and length.

Parameters:
position (vec3) — The starting position.
direction (vec3) — The direction vector.
width (number) — The width of the rectangle.
length (number) — The length of the rectangle.

Returns: rectangle — A new rectangle instance.

is_inside(point, hitbox)​

Checks if a point is inside the rectangle.

Parameters:
point (vec3) — The point to check.
hitbox (number) — The hitbox radius to consider.

Returns: boolean — true if the point is inside; otherwise, false.

get_units_inside(units_list)​

Retrieves units within the rectangle.

Parameters:
units_list (table<game_object>, optional) — List of units to check. If not provided, retrieves all units around the rectangle's origin.

Returns: table<game_object> — A table of units inside the rectangle.

get_allies_inside(units_list_override)​

Retrieves allies within the rectangle.

Parameters:
units_list_override (table<game_object>, optional) — List of units to check. If not provided, retrieves all units around the rectangle's origin.

Returns: table<game_object> — A table of allies inside the rectangle.

get_enemies_inside(units_list_override)​

Retrieves enemies within the rectangle.

Parameters:
units_list_override (table<game_object>, optional) — List of units to check. If not provided, retrieves all units around the rectangle's origin.

Returns: table<game_object> — A table of enemies inside the rectangle.

draw(custom_height)​

Draws the rectangle.

Parameters:
custom_height (number, optional) — Custom height to draw the rectangle.

Returns: nil

draw_with_counter(count)​

Draws the rectangle and the number of units hit.

Parameters:
count (number, optional) — Number of units hit. If not provided, calculates the number of units inside the rectangle.

Returns: nil

Cone​

The cone class represents a cone with a center point, radius, angle, and direction.

Properties​
center: vec3 — The center position of the cone.
radius: number — The radius of the cone.
angle: number — The angle of the cone in degrees.
direction: vec3 — The direction vector of the cone.
Methods​
create(center, radius, angle, direction)​

Creates a cone given a center position, radius, angle, and direction.

Parameters:
center (vec3) — The center position of the cone.
radius (number) — The radius of the cone.
angle (number) — The angle of the cone in degrees.
direction (vec3) — The direction vector the cone is facing.

Returns: cone — A new cone instance.

is_inside(point_position, hitbox)​

Checks if a point is inside the cone.

Parameters:
point_position (vec3) — The position of the point to check.
hitbox (number) — The hitbox radius to consider.

Returns: boolean — true if the point is inside; otherwise, false.

get_units_inside(units_list)​

Retrieves units within the cone.

Parameters:
units_list (table<game_object>, optional) — List of units to check. If not provided, retrieves all units around the cone's center.

Returns: table<game_object> — A table of units inside the cone.

get_allies_inside(units_list_override)​

Retrieves allies within the cone.

Parameters:
units_list_override (table<game_object>, optional) — List of units to check. If not provided, retrieves all units around the cone's center.

Returns: table<game_object> — A table of allies inside the cone.

get_enemies_inside(units_list_override)​

Retrieves enemies within the cone.

Parameters:
units_list_override (table<game_object>, optional) — List of units to check. If not provided, retrieves all units around the cone's center.

Returns: table<game_object> — A table of enemies inside the cone.

draw(custom_height)​

Draws the cone.

Parameters:
custom_height (number, optional) — Custom height to draw the cone.

Returns: nil

draw_with_counter(count)​

Draws the cone and the number of units hit.

Parameters:
count (number, optional) — Number of units hit. If not provided, calculates the number of units inside the cone.

Returns: nil

Examples​
Creating and Using a Circle​
-- load the circle class

---@type circle

local circle = require("common/geometry/circle")



local function generate_and_draw_circle_with_hit_count()

    local local_player = core.object_manager.get_local_player()

    if not local_player then

        return

    end

    -- get the player's position

    local player_position = core.object_manager.get_local_player():get_position()



    -- create a circle with a radius of 10 units, for example

    local my_circle = circle:create(player_position, 10.0)



    -- get enemies inside the circle

    local enemies = my_circle:get_enemies_inside()



    -- draw the circle and the number of enemies inside

    my_circle:draw_with_counter(#enemies)

end



core.register_on_render_callback(function()

    generate_and_draw_circle_with_hit_count()

end)


This is what you should be seeing after running that code:

Creating and Using a Rectangle​
-- load the rectangle class

---@type rectangle

local rectangle = require("common/geometry/rectangle")



---@type vec3

local vec3 = require("common/geometry/vector_3")



local function generate_and_draw_rect_with_ally_hit_count()

    local local_player = core.object_manager.get_local_player()

    if not local_player then

        return

    end



    -- define origin and destination positions

    local origin = local_player:get_position()

    local destination = origin + vec3.new(20, 0, 0)



    -- create a rectangle of width 5 units

    local my_rectangle = rectangle:create(origin, destination, 5.0)



    -- get allies inside the rectangle

    local allies = my_rectangle:get_allies_inside()



    -- Draw the rectangle

    my_rectangle:draw_with_counter(#allies)

end



core.register_on_render_callback(function()

    generate_and_draw_rect_with_ally_hit_count()

end)


This is what you should be seeing after running that code:

Creating and Using a Cone​
-- load the cone class

---@type cone

local cone = require("common/geometry/cone")



-- load the vec3 class

---@type vec3

local vec3 = require("common/geometry/vector_3")



local function generate_and_draw_cone_with_unit_hit_count()

    local local_player = core.object_manager.get_local_player()

    if not local_player then

        return

    end



    -- get the player's position and facing direction

    local position = local_player:get_position()

    local origin = local_player:get_position()

    local destination = origin + vec3.new(20, 0, 0)



    -- create a cone with a radius of 10 yds and an angle of 45 degrees

    local my_cone = cone:create(position, destination, 10.0, 45)



    -- draw the cone

    my_cone:draw_with_counter()



    my_cone:draw()

end



core.register_on_render_callback(function()

    generate_and_draw_cone_with_unit_hit_count()

end)


This is what you should be seeing after running that code:

NOTE

The shaders for the cones are still under development. It will be added in the future, that's why they look worse than the other geometries. Stay tuned for the shaders update!

Notes​
The vec3 type represents a 3D vector with x, y, and z coordinates. See Vectors (vec3) for more details.
The game_object type refers to any entity within the game world, such as players, NPCs, or items. See Game Object - Functions for more details.