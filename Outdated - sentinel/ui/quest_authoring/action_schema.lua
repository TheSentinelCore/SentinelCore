-- sentinel/ui/quest_authoring/action_schema.lua
-- Defines the fields, types, defaults, and metadata for every action type
-- available in the IDE palette. Used by:
--   - Action Palette (grouping, description, suggestions)
--   - Properties Pane (dynamic form generation, editable fields)
--   - Context (default args when adding a new action)
--   - Validation (required-field checks)

local ActionSchema = {}

-- Field descriptor:
--   key        string   Arg key in action.args
--   label      string   Display label in the Properties form
--   type       string   "string" | "number" | "boolean" | "vec3"
--   default    any      Default value (nil = empty string / 0 / false)
--   required   bool     If true, validation fails when empty
--   desc       string   Tooltip / help text
--   min        number?  For number fields, lower bound
--   max        number?  For number fields, upper bound

local F = function(key, label, ftype, default, required, desc, extra)
  local field = { key = key, label = label, type = ftype or "string",
                  default = default, required = required or false, desc = desc or "" }
  if extra then for k, v in pairs(extra) do field[k] = v end end
  return field
end

-- ── Registry ──────────────────────────────────────────────────────────
-- Each entry: { type, category, desc, fields = { ... } }

ActionSchema.TYPES = {

  -- ── Movement ───────────────────────────────────────────────────────
  TravelTo = {
    category  = "movement",
    desc      = "Move to a destination (NPC, coordinates, or named location)",
    fields = {
      F("method",   "Method",     "string", "walk",  false, "walk / fly / boat / auto"),
      F("to",       "Destination","string", nil,     true,  "NPC name, zone name, or x,y,z"),
      F("from",     "From",       "string", "",      false, "Starting point (omit = current pos)"),
    },
  },
  Wait = {
    category  = "movement",
    desc      = "Pause for a duration (travel cooldown, zeppelin wait, etc.)",
    fields = {
      F("duration_s", "Seconds", "number", 5, true, "Duration in seconds", { min = 0, max = 3600 }),
    },
  },
  Fish = {
    category  = "movement",
    desc      = "Fish at a fishing node or open water",
    fields = {
      F("duration_s", "Seconds", "number", 30, false, "How long to fish", { min = 1, max = 600 }),
      F("location",   "Location","string", "",  false, '"current" or coordinates'),
    },
  },

  -- ── Combat ─────────────────────────────────────────────────────────
  KillCreature = {
    category  = "combat",
    desc      = "Kill one or more creatures by name or ID",
    fields = {
      F("creature_name", "Creature",  "string", nil,     true,  "Name or numeric creature ID"),
      F("count",         "Count",     "number", 1,       false, "How many to kill", { min = 1, max = 999 }),
      F("radius",        "Radius yd", "number", 35,      false, "Search radius around current pos", { min = 5, max = 200 }),
      F("quest_id",      "Quest ID",  "number", nil,     false, "Link to a specific quest objective"),
    },
  },
  Loot = {
    category  = "combat",
    desc      = "Loot quest or grinding items from killed creatures",
    fields = {
      F("item_name", "Item",   "string", nil, true,  "Item name or numeric item ID"),
      F("count",     "Count",  "number", 1,  false, "How many to collect", { min = 1, max = 999 }),
    },
  },

  -- ── Interaction ────────────────────────────────────────────────────
  TalkToNPC = {
    category  = "interaction",
    desc      = "Talk to an NPC (dialogue, gossip, quest text)",
    fields = {
      F("npc_name",  "NPC",     "string", nil,  true,  "NPC name or numeric entry ID"),
      F("quest_id",  "Quest ID","number", nil,  false, "Quest context for dialogue"),
    },
  },
  AcceptQuest = {
    category  = "interaction",
    desc      = "Accept / pick up a quest from an NPC",
    fields = {
      F("quest_id",  "Quest ID", "number", nil, true,  "Quest ID to accept"),
      F("npc_name",  "NPC",      "string", "",  false, "Quest giver (for travel targeting)"),
    },
  },
  TurnInQuest = {
    category  = "interaction",
    desc      = "Turn in a completed quest",
    fields = {
      F("quest_id",  "Quest ID", "number", nil, true,  "Quest ID to turn in"),
      F("npc_name",  "NPC",      "string", "",  false, "Quest receiver (for travel targeting)"),
    },
  },
  AbandonQuest = {
    category  = "interaction",
    desc      = "Abandon a quest (drop from quest log)",
    fields = {
      F("quest_id",  "Quest ID", "number", nil, true, "Quest ID to abandon"),
    },
  },
  Vendor = {
    category  = "interaction",
    desc      = "Use a vendor to sell junk or buy supplies",
    fields = {
      F("npc_name",  "NPC",       "string", "",    false, "Vendor name (omit = nearest)"),
      F("buy_items", "Buy Items", "string", "",    false, "Comma-separated item names to buy"),
    },
  },
  Repair = {
    category  = "interaction",
    desc      = "Repair gear at a vendor or NPC",
    fields = {
      F("npc_name",           "NPC",       "string", "",    false, "Repair NPC (omit = nearest)"),
      F("durability_threshold", "Threshold %", "number", 50, false, "Repair when durability is below this %", { min = 1, max = 100 }),
    },
  },

  -- ── Quest ──────────────────────────────────────────────────────────
  CollectItem = {
    category  = "quest",
    desc      = "Collect an item from the world (herbs, minerals, objects)",
    fields = {
      F("item_name", "Item",  "string", nil,  true,  "Item name or numeric item ID"),
      F("count",     "Count", "number", 1,    false, "How many to collect", { min = 1, max = 999 }),
    },
  },
  GoToGameObject = {
    category  = "quest",
    desc      = "Interact with a game object (chest, door, altar, etc.)",
    fields = {
      F("gameobject_name", "Object", "string", nil, true, "Object name or numeric entry ID"),
    },
  },

  -- ── Utility ────────────────────────────────────────────────────────
  Marker = {
    category  = "movement",
    desc      = "Set a named position marker on the map",
    fields = {
      F("x", "X", "number", 0, true, "World X coordinate", { min = -20000, max = 20000 }),
      F("y", "Y", "number", 0, true, "World Y coordinate", { min = -20000, max = 20000 }),
      F("z", "Z", "number", 0, false, "World Z coordinate (height)", { min = -2000, max = 2000 }),
      F("label", "Label", "string", "", false, "Display label on the map"),
    },
  },
}

-- ── Category metadata ─────────────────────────────────────────────────
ActionSchema.CATEGORIES = {
  movement    = { label = "Movement",    color_key = "cat_movement" },
  combat      = { label = "Combat",      color_key = "cat_combat" },
  interaction = { label = "Interaction", color_key = "cat_interaction" },
  quest       = { label = "Quest",       color_key = "cat_quest" },
}

-- ── Helpers ───────────────────────────────────────────────────────────

--- Look up the schema for an action type string.
--- @param action_type string
--- @return table|nil  schema entry or nil
function ActionSchema.get(action_type)
  return ActionSchema.TYPES[action_type]
end

--- Return an ordered list of { type, category, desc, fields } for iteration.
function ActionSchema.all()
  local out = {}
  for name, entry in pairs(ActionSchema.TYPES) do
    out[#out + 1] = setmetatable({ type = name }, { __index = entry })
  end
  -- Stable sort by category then type
  table.sort(out, function(a, b)
    if a.category ~= b.category then return a.category < b.category end
    return a.type < b.type
  end)
  return out
end

--- Return types grouped by category (ordered).
function ActionSchema.by_category()
  local grouped = {}
  local order = {}
  for name, entry in pairs(ActionSchema.TYPES) do
    local cat = entry.category
    if not grouped[cat] then
      grouped[cat] = {}
      order[#order + 1] = cat
    end
    grouped[cat][#grouped[cat] + 1] = setmetatable({ type = name }, { __index = entry })
  end
  -- Sort within each category
  for _, cat in ipairs(order) do
    table.sort(grouped[cat], function(a, b) return a.type < b.type end)
  end
  return grouped, order
end

--- Build default args table for a given action type.
function ActionSchema.default_args(action_type)
  local schema = ActionSchema.TYPES[action_type]
  if not schema then return {} end
  local args = {}
  for _, f in ipairs(schema.fields) do
    if f.default ~= nil then
      args[f.key] = f.default
    end
  end
  return args
end

--- Validate that an action's args satisfy the schema.
--- @return boolean ok, string[] errors
function ActionSchema.validate(action_type, args)
  local schema = ActionSchema.TYPES[action_type]
  if not schema then return true, {} end  -- unknown type = pass-through
  args = args or {}
  local errs = {}
  for _, f in ipairs(schema.fields) do
    local v = args[f.key]
    if f.required and (v == nil or v == "") then
      errs[#errs + 1] = string.format("'%s' is required for %s", f.label, action_type)
    end
    if v ~= nil and v ~= "" then
      if f.type == "number" then
        local n = tonumber(v)
        if not n then
          errs[#errs + 1] = string.format("'%s' must be a number for %s", f.label, action_type)
        else
          if f.min and n < f.min then
            errs[#errs + 1] = string.format("'%s' must be >= %s for %s", f.label, tostring(f.min), action_type)
          end
          if f.max and n > f.max then
            errs[#errs + 1] = string.format("'%s' must be <= %s for %s", f.label, tostring(f.max), action_type)
          end
        end
      end
    end
  end
  return #errs == 0, errs
end

return ActionSchema
