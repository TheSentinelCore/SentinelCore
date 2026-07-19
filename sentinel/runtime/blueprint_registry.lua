-- sentinel/runtime/blueprint_registry.lua
-- Registry of standard Blueprint definitions for expansion

local BlueprintRegistry = {}
BlueprintRegistry.__index = BlueprintRegistry

---Create a new BlueprintRegistry
---@return table BlueprintRegistry instance
function BlueprintRegistry:new()
    local o = setmetatable({}, BlueprintRegistry)
    o._blueprints = {}
    o:_register_standard_blueprints()
    return o
end

---Register all standard Blueprint definitions
function BlueprintRegistry:_register_standard_blueprints()
    self._blueprints["quest_hub"] = {
        id = "quest_hub",
        category = "quest",
        parameters = {
            { name = "quest_giver", type = "npc", required = false },
            { name = "vendor", type = "npc", required = false },
            { name = "trainer", type = "npc", required = false },
            { name = "repair", type = "boolean", required = false },
            { name = "train", type = "boolean", required = false },
            { name = "accept_all", type = "boolean", required = false },
        },
        expand = function(params)
            local actions = {}
            local action_index = 0

            if params.quest_giver then
                action_index = action_index + 1
                table.insert(actions, {
                    id = "bp-talk-" .. tostring(action_index),
                    action_type = "talk_to_npc",
                    params = { npc_guid = params.quest_giver.guid, gossip_option = "quest" },
                })

                if params.accept_all and params.quests then
                    for _, quest_id in ipairs(params.quests) do
                        action_index = action_index + 1
                        table.insert(actions, {
                            id = "bp-pickup-" .. tostring(quest_id),
                            action_type = "pickup_quest",
                            params = { quest_id = quest_id, npc_guid = params.quest_giver.guid },
                        })
                    end
                end
            end

            if params.vendor then
                action_index = action_index + 1
                table.insert(actions, {
                    id = "bp-vendor-" .. tostring(action_index),
                    action_type = "vendor",
                    params = {
                        npc_guid = params.vendor.guid,
                        vendor = params.vendor,
                    },
                })

                if params.repair then
                    action_index = action_index + 1
                    table.insert(actions, {
                        id = "bp-repair-" .. tostring(action_index),
                        action_type = "repair",
                        params = {
                            npc_guid = params.vendor.guid,
                            vendor = params.vendor,
                        },
                    })
                end
            end

            if params.trainer and params.train then
                action_index = action_index + 1
                table.insert(actions, {
                    id = "bp-train-" .. tostring(action_index),
                    action_type = "train",
                    params = {
                        npc_guid = params.trainer.guid,
                        trainer = params.trainer,
                    },
                })
            end

            return actions
        end,
    }

    self._blueprints["vendor_stop"] = {
        id = "vendor_stop",
        category = "inventory",
        parameters = {
            { name = "vendor", type = "npc", required = false },
            { name = "repair", type = "boolean", required = false },
            { name = "sell_gray", type = "boolean", required = false },
            { name = "sell_white", type = "boolean", required = false },
            { name = "buy_food", type = "boolean", required = false },
            { name = "buy_water", type = "boolean", required = false },
        },
        expand = function(params)
            local actions = {}
            local action_index = 0

            if params.vendor then
                action_index = action_index + 1
                table.insert(actions, {
                    id = "bp-vendor-" .. tostring(action_index),
                    action_type = "vendor",
                    params = {
                        npc_guid = params.vendor.guid,
                        vendor = params.vendor,
                    },
                })

                if params.repair then
                    action_index = action_index + 1
                    table.insert(actions, {
                        id = "bp-repair-" .. tostring(action_index),
                        action_type = "repair",
                        params = {
                            npc_guid = params.vendor.guid,
                            vendor = params.vendor,
                        },
                    })
                end
            end

            return actions
        end,
    }

    self._blueprints["trainer_stop"] = {
        id = "trainer_stop",
        category = "inventory",
        parameters = {
            { name = "trainer", type = "npc", required = false },
        },
        expand = function(params)
            local actions = {}
            local action_index = 0

            if params.trainer then
                action_index = action_index + 1
                table.insert(actions, {
                    id = "bp-train-" .. tostring(action_index),
                    action_type = "train",
                    params = {
                        npc_guid = params.trainer.guid,
                        trainer = params.trainer,
                    },
                })
            end

            return actions
        end,
    }

    self._blueprints["goto"] = {
        id = "goto",
        category = "travel",
        parameters = {
            { name = "target", type = "waypoint", required = true },
            { name = "arrival_radius", type = "number", required = false },
        },
        expand = function(params)
            local actions = {}
            table.insert(actions, {
                id = "bp-goto-1",
                action_type = "goto",
                params = { target = params.target, arrival_radius = params.arrival_radius or 5 },
            })
            return actions
        end,
    }
    self._blueprints["grind_area"] = {
        id = "grind_area",
        category = "combat",
        parameters = {
            { name = "creatures", type = "table", required = false },
            { name = "position", type = "position", required = false },
            { name = "radius", type = "number", required = false },
        },
        expand = function(params)
            local actions = {}
            local area = params.position or { x = 0, y = 0, z = 0 }
            table.insert(actions, {
                id = "bp-grind-1",
                action_type = "grind_area",
                params = {
                    position = area,
                    radius = params.radius or 50,
                    mob_ids = params.creatures or {},
                },
            })
            return actions
        end,
    }

    self._blueprints["travel_hub"] = {
        id = "travel_hub",
        category = "travel",
        parameters = {
            { name = "destination", type = "position", required = false },
            { name = "arrival_radius", type = "number", required = false },
            { name = "flight_master", type = "npc", required = false },
        },
        expand = function(params)
            local actions = {}
            if params.destination then
                table.insert(actions, {
                    id = "bp-travel-goto",
                    action_type = "goto",
                    params = { target = params.destination, arrival_radius = params.arrival_radius or 5 },
                })
            end
            if params.flight_master then
                table.insert(actions, {
                    id = "bp-travel-flight",
                    action_type = "flight_path",
                    params = { npc_guid = params.flight_master.guid },
                })
            end
            return actions
        end,
    }

    self._blueprints["flight_unlock"] = {
        id = "flight_unlock",
        category = "travel",
        parameters = {
            { name = "flight_master", type = "npc", required = false },
            { name = "destination", type = "number", required = false },
        },
        expand = function(params)
            local actions = {}
            if params.flight_master then
                table.insert(actions, {
                    id = "bp-flight-1",
                    action_type = "flight_path",
                    params = { npc_guid = params.flight_master.guid },
                })
            end
            return actions
        end,
    }

    self._blueprints["repair_stop"] = {
        id = "repair_stop",
        category = "vendor",
        parameters = {
            { name = "vendor", type = "npc", required = false },
        },
        expand = function(params)
            local actions = {}
            if params.vendor then
                table.insert(actions, {
                    id = "bp-repair-1",
                    action_type = "repair",
                    params = { npc_guid = params.vendor.guid },
                })
            end
            return actions
        end,
    }

    self._blueprints["mailbox_stop"] = {
        id = "mailbox_stop",
        category = "vendor",
        parameters = {
            { name = "mailbox", type = "object", required = false },
        },
        expand = function(params)
            local actions = {}
            if params.mailbox then
                table.insert(actions, {
                    id = "bp-mailbox-1",
                    action_type = "mailbox",
                    params = { object_guid = params.mailbox.guid },
                })
            end
            return actions
        end,
    }

    self._blueprints["bank_stop"] = {
        id = "bank_stop",
        category = "vendor",
        parameters = {
            { name = "banker", type = "npc", required = false },
        },
        expand = function(params)
            local actions = {}
            if params.banker then
                table.insert(actions, {
                    id = "bp-bank-1",
                    action_type = "bank",
                    params = { npc_guid = params.banker.guid },
                })
            end
            return actions
        end,
    }

    self._blueprints["death_skip"] = {
        id = "death_skip",
        category = "combat",
        parameters = {},
        expand = function(params)
            local actions = {}
            table.insert(actions, {
                id = "bp-death-skip-1",
                action_type = "death_skip",
                params = {},
            })
            return actions
        end,
    }

    self._blueprints["stuck_recovery_marker"] = {
        id = "stuck_recovery_marker",
        category = "navigation",
        parameters = {
            { name = "marker", type = "string", required = false },
        },
        expand = function(params)
            local actions = {}
            table.insert(actions, {
                id = "bp-stuck-1",
                action_type = "dungeon_marker",
                params = { marker = params.marker or "stuck_recovery" },
            })
            return actions
        end,
    }

    self._blueprints["set_variable"] = {
        id = "set_variable",
        category = "utils",
        parameters = {
            { name = "name", type = "string", required = false },
            { name = "value", type = "any", required = false },
        },
        expand = function(params)
            local actions = {}
            table.insert(actions, {
                id = "bp-var-1",
                action_type = "set_variable",
                params = { name = params.name, value = params.value },
            })
            return actions
        end,
    }

    self._blueprints["conditional_branch"] = {
        id = "conditional_branch",
        category = "utils",
        parameters = {
            { name = "condition", type = "table", required = false },
            { name = "then_actions", type = "table", required = false },
            { name = "else_actions", type = "table", required = false },
        },
        expand = function(params)
            local actions = {}
            table.insert(actions, {
                id = "bp-branch-1",
                action_type = "branch",
                params = { condition = params.condition },
            })
            return actions
        end,
    }

    self._blueprints["wait"] = {
        id = "wait",
        category = "utils",
        parameters = {
            { name = "duration_ms", type = "number", required = false },
        },
        expand = function(params)
            local actions = {}
            table.insert(actions, {
                id = "bp-wait-1",
                action_type = "wait",
                params = { duration_ms = params.duration_ms or 1000 },
            })
            return actions
        end,
    }

    self._blueprints["use_item"] = {
        id = "use_item",
        category = "inventory",
        parameters = {
            { name = "item_id", type = "number", required = false },
            { name = "item", type = "number", required = false },
        },
        expand = function(params)
            local actions = {}
            table.insert(actions, {
                id = "bp-use-item-1",
                action_type = "use_item",
                params = { item_id = params.item_id or params.item },
            })
            return actions
        end,
    }

    self._blueprints["gossip_sequence"] = {
        id = "gossip_sequence",
        category = "quest",
        parameters = {
            { name = "npc", type = "npc", required = false },
            { name = "gossip_options", type = "table", required = false },
        },
        expand = function(params)
            local actions = {}
            local i = 1
            while params.gossip_options and params.gossip_options[i] do
                table.insert(actions, {
                    id = "bp-gossip-" .. i,
                    action_type = "talk_to_npc",
                    params = { npc_guid = params.npc.guid, gossip_option = params.gossip_options[i] },
                })
                i = i + 1
            end
            return actions
        end,
    }
end

---Get a blueprint definition by ID
---@param blueprint_id string The blueprint ID
---@return table|nil Blueprint definition or nil if not found
function BlueprintRegistry:get(blueprint_id)
    return self._blueprints[blueprint_id]
end

---Check if a blueprint exists
---@param blueprint_id string The blueprint ID
---@return boolean
function BlueprintRegistry:has(blueprint_id)
    return self._blueprints[blueprint_id] ~= nil
end

---Get all registered blueprint IDs
---@return table Array of blueprint IDs
function BlueprintRegistry:list_ids()
    local ids = {}
    for id, _ in pairs(self._blueprints) do
        table.insert(ids, id)
    end
    return ids
end

---Register a custom blueprint
---@param blueprint table Blueprint definition with id and expand function
function BlueprintRegistry:register(blueprint)
    if blueprint and blueprint.id then
        self._blueprints[blueprint.id] = blueprint
    end
end

---Expand a Blueprint reference into primitive actions
---@param action table Action with blueprint_id and params
---@return table Array of expanded primitive actions
function BlueprintRegistry:expand(action)
    local blueprint = self._blueprints[action.blueprint_id]
    if not blueprint then
        return nil
    end

    if type(blueprint.expand) ~= "function" then
        return nil
    end

    local params = action.params or {}
    return blueprint.expand(params)
end

---Check if an action is a blueprint reference
---@param action table Action to check
---@return boolean
function BlueprintRegistry:is_blueprint(action)
    return action.action_type == "blueprint" and action.blueprint_id ~= nil
end

return BlueprintRegistry