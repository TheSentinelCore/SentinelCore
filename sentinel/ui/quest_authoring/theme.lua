-- sentinel/ui/quest_authoring/theme.lua
-- Shared theme + color/vec2 helpers for the Quest Authoring IDE.
-- Uses the same fallback pattern as ui/lib/sentinel_ui so it loads even when
-- common/color and common/geometry/vector_2 are unavailable (e.g. tests).

local function require_or(module_name, fallback)
  local ok, mod = pcall(require, module_name)
  if ok and mod ~= nil then return mod end
  return fallback
end

local color = require_or("common/color", {
  new = function(r, g, b, a) return { r = r or 0, g = g or 0, b = b or 0, a = a or 255 } end,
  white = function(a) return { r = 255, g = 255, b = 255, a = a or 255 } end,
})

local vec2 = require_or("common/geometry/vector_2", {
  new = function(x, y) return { x = x or 0, y = y or 0 } end,
})

-- Sentinel-derived dark theme.
local THEME = {
  background   = color.new(14, 16, 20, 240),
  panel_bg     = color.new(22, 26, 32, 235),
  panel_border = color.new(52, 60, 72, 200),
  accent       = color.new(86, 140, 210, 255),
  text         = color.new(220, 225, 232, 245),
  text_dim     = color.new(160, 170, 182, 200),
  text_error   = color.new(230, 80, 70, 255),
  text_warn    = color.new(235, 200, 50, 255),
  selected     = color.new(86, 140, 210, 70),
  hover        = color.new(38, 44, 52, 255),
  row_sep      = color.new(80, 90, 105, 45),
  green        = color.new(72, 200, 110, 255),
  red          = color.new(230, 80, 70, 255),
  yellow       = color.new(235, 200, 50, 255),
  orange       = color.new(235, 150, 40, 255),
  input_bg     = color.new(28, 32, 40, 255),
  input_border = color.new(52, 60, 72, 255),
}

-- Flat color table used by the panes (Theme.colors.*).
local COLORS = {
  bg            = THEME.background,
  bg_alt        = THEME.panel_bg,
  border        = THEME.panel_border,
  grid          = THEME.row_sep,
  text          = THEME.text,
  text_dim      = THEME.text_dim,
  accent        = THEME.accent,
  button        = THEME.input_bg,
  button_hover  = THEME.hover,
  selected      = THEME.selected,
  error         = THEME.text_error,
  warning       = THEME.text_warn,
  red           = THEME.red,
  green         = THEME.green,
  white         = color.white(),
  player        = THEME.green,
  marker        = THEME.yellow,
  marker_npc    = THEME.accent,
  path          = THEME.orange,
  timeline_block = THEME.panel_border,
  timeline_sel  = THEME.accent,
  cat_movement  = THEME.green,
  cat_combat    = THEME.red,
  cat_interaction = THEME.accent,
  cat_quest     = THEME.yellow,
  tooltip_bg    = THEME.background,
  tooltip_text  = THEME.text,
}

-- Map an action type to one of the four palette categories.
local CATEGORY_LOOKUP = {
  Travel = "movement", MoveTo = "movement", UseItemAt = "movement",
  AttackTarget = "combat", KillTarget = "combat", Pull = "combat",
  InteractNPC = "interaction", InteractObject = "interaction", Loot = "interaction",
  Vendor = "interaction", Repair = "interaction", Fish = "interaction", Mail = "interaction",
  AcceptQuest = "quest", TurnInQuest = "quest", PickupQuest = "quest", TurnIn = "quest",
  Wait = "interaction", Hearth = "interaction", Train = "interaction",
}
local function category_for_type(action_type)
  return CATEGORY_LOOKUP[action_type] or "interaction"
end

local function tbl_to_str(t)
  if type(t) ~= "table" then return tostring(t) end
  local parts = {}
  for k, v in pairs(t) do
    parts[#parts + 1] = tostring(k) .. "=" .. tostring(v)
  end
  return "{" .. table.concat(parts, ", ") .. "}"
end

return {
  color = color,
  vec2 = vec2,
  theme = THEME,
  colors = COLORS,
  category_for_type = category_for_type,
  tbl_to_str = tbl_to_str,
}
