local ObjectiveApproach = {}

local CAPTURE_TYPES = {
    GRAVEYARD = true,
    TOWER = true,
    NODE = true,
    FLAG = true,
}

local function num(value)
    return tonumber(value) or 0
end

local function copy_vec3(vec)
    if type(vec) ~= "table" then
        return nil
    end
    return {
        x = num(vec.x),
        y = num(vec.y),
        z = num(vec.z),
    }
end

local function distance(a, b)
    if type(a) ~= "table" or type(b) ~= "table" then
        return 99999
    end
    local dx = num(a.x) - num(b.x)
    local dy = num(a.y) - num(b.y)
    local dz = num(a.z) - num(b.z)
    return math.sqrt((dx * dx) + (dy * dy) + (dz * dz))
end

local function ring_radius(objective_type, settings)
    local kind = tostring(objective_type or "")
    if kind == "GRAVEYARD" then
        return tonumber(settings and settings.objective_ring_radius_gy) or 7
    end
    if kind == "TOWER" then
        return tonumber(settings and settings.objective_ring_radius_tower) or 9
    end
    if kind == "NODE" then
        return tonumber(settings and settings.objective_ring_radius_node) or 8
    end
    if kind == "FLAG" then
        return tonumber(settings and settings.objective_ring_radius_flag) or 6
    end
    return tonumber(settings and settings.objective_approach_standoff_yd) or 8
end

local function variant_count(settings)
    local count = math.floor(tonumber(settings and settings.objective_ring_variant_count) or 6)
    if count < 1 then
        count = 1
    end
    return count
end

local function objective_matches_waypoint(objective, waypoint)
    if type(objective) ~= "table" or type(waypoint) ~= "table" then
        return false
    end
    return distance(objective, waypoint) <= 2.0
end

function ObjectiveApproach.is_capture_objective(objective)
    if type(objective) ~= "table" then
        return false
    end
    return CAPTURE_TYPES[tostring(objective.type or "")] == true
end

function ObjectiveApproach.new_runtime(settings)
    return {
        mode = tostring(settings and settings.objective_approach_mode or "adaptive_ring"),
        objective_id = "",
        stage = "ring",
        variant = 1,
        last_variant_shift_at_ms = 0,
        last_progress_signature = nil,
        last_progress_at_ms = 0,
    }
end

function ObjectiveApproach.ensure_runtime(runtime, objective, settings)
    runtime = runtime or ObjectiveApproach.new_runtime(settings)
    local id = tostring(objective and objective.id or "")
    local has_anchor = type(objective) == "table" and type(objective.approach_anchor) == "table"
    runtime.mode = has_anchor and "anchor_then_ring" or tostring(settings and settings.objective_approach_mode or runtime.mode or "adaptive_ring")
    if runtime.objective_id ~= id then
        runtime.objective_id = id
        runtime.stage = has_anchor and "anchor" or "ring"
        runtime.variant = 1
        runtime.last_variant_shift_at_ms = 0
        runtime.last_progress_signature = nil
        runtime.last_progress_at_ms = 0
    end
    return runtime
end

function ObjectiveApproach.maybe_shift_variant(runtime, objective, settings, now_ms, reason)
    runtime = ObjectiveApproach.ensure_runtime(runtime, objective, settings)
    local shift_ms = 1250
    if reason and (num(now_ms) - num(runtime.last_variant_shift_at_ms)) >= shift_ms then
        local has_anchor = type(objective) == "table" and type(objective.approach_anchor) == "table"
        if has_anchor and runtime.stage == "anchor" then
            runtime.stage = "ring"
            runtime.variant = 1
        else
            runtime.variant = (math.max(1, num(runtime.variant)) % variant_count(settings)) + 1
        end
        runtime.last_variant_shift_at_ms = num(now_ms)
        runtime.last_shift_reason = tostring(reason)
    end
    return runtime
end

function ObjectiveApproach.update_runtime(runtime, objective, player_pos, nav_state, nav_result, nav_progress, settings, now_ms)
    runtime = ObjectiveApproach.ensure_runtime(runtime, objective, settings)
    if not ObjectiveApproach.is_capture_objective(objective) then
        return runtime
    end

    local progress = type(nav_progress) == "table" and nav_progress or {}
    local signature = tostring(nav_state or "") .. ":" .. tostring(progress.path_index or 0) .. ":" .. tostring(progress.distance_remaining or 0)
    if runtime.last_progress_signature ~= signature then
        runtime.last_progress_signature = signature
        runtime.last_progress_at_ms = num(now_ms)
    end

    local capture_radius = tonumber(settings and settings.capture_radius) or 12
    local center = copy_vec3(objective)
    local outside_capture = distance(player_pos, center) > math.max(capture_radius, ring_radius(objective.type, settings))
    local stalled = outside_capture and (num(now_ms) - num(runtime.last_progress_at_ms)) >= 1500

    local reason = nil
    if nav_result == "failed" then
        reason = "nav_failed"
    elseif nav_state == "stuck" then
        reason = "nav_stuck"
    elseif stalled then
        reason = "progress_stalled"
    end

    return ObjectiveApproach.maybe_shift_variant(runtime, objective, settings, now_ms, reason)
end

function ObjectiveApproach.compute_nav_target(player_pos, objective, settings, runtime)
    local center = copy_vec3(objective)
    if not center then
        return nil
    end
    if not ObjectiveApproach.is_capture_objective(objective) then
        return center
    end

    runtime = ObjectiveApproach.ensure_runtime(runtime, objective, settings)
    if runtime.stage == "anchor" and type(objective.approach_anchor) == "table" then
        return copy_vec3(objective.approach_anchor)
    end

    local mode = tostring(settings and settings.objective_approach_mode or "adaptive_ring")
    if runtime.mode ~= "adaptive_ring" and runtime.mode ~= "anchor_then_ring" and mode ~= "adaptive_ring" then
        return center
    end

    local count = variant_count(settings)
    local variant = math.max(1, math.floor(num(runtime.variant)))
    if variant > count then
        variant = ((variant - 1) % count) + 1
    end

    local base_angle = 0
    if type(player_pos) == "table" then
        local dx = num(player_pos.x) - center.x
        local dy = num(player_pos.y) - center.y
        if math.abs(dx) > 0.001 or math.abs(dy) > 0.001 then
            base_angle = math.atan2(dy, dx)
        end
    end

    local angle_step = (math.pi * 2) / count
    local angle = base_angle + ((variant - 1) * angle_step)
    local radius = ring_radius(objective.type, settings)
    return {
        x = center.x + math.cos(angle) * radius,
        y = center.y + math.sin(angle) * radius,
        z = center.z,
    }
end

function ObjectiveApproach.offset_route_nodes(route_nodes, objectives_by_id, settings, runtime)
    if type(route_nodes) ~= "table" or #route_nodes == 0 or type(objectives_by_id) ~= "table" then
        return route_nodes
    end

    local offset = {}
    for index, node in ipairs(route_nodes) do
        local matched = nil
        for _, objective in pairs(objectives_by_id) do
            if ObjectiveApproach.is_capture_objective(objective) and objective_matches_waypoint(objective, node) then
                matched = objective
                break
            end
        end

        if not matched then
            offset[#offset + 1] = copy_vec3(node)
        else
            local prev = route_nodes[index - 1]
            if type(matched.approach_anchor) == "table" then
                offset[#offset + 1] = copy_vec3(matched.approach_anchor)
            else
                local local_runtime = ObjectiveApproach.ensure_runtime(runtime, matched, settings)
                offset[#offset + 1] = ObjectiveApproach.compute_nav_target(prev, matched, settings, local_runtime) or copy_vec3(node)
            end
        end
    end

    return offset
end

return ObjectiveApproach
