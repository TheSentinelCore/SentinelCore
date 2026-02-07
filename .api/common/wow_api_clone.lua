
---@meta
---@diagnostic disable: missing-fields, undefined-global, lowercase-global

-- NOTE FOR DEVS:
-- These globals COME FROM require("common/wow_api_clone").
-- If you do NOT require it somewhere in your session, these names will be nil at runtime.
-- This file only provides IntelliSense (sumneko) signatures.

---@param ... any
function print(...) end
---@param fmt string
---@param ... any
function printf(fmt, ...) end

---@param filename string
---@param ... any
function log(filename, ...) end
---@param filename string
---@param fmt string
---@param ... any
function logf(filename, fmt, ...) end

---@class game_object  -- forward-declare so the alias below works

---A WoW-like unit token or a real game_object
---@alias WowUnit string|game_object

-- Function type aliases (use alias, NOT class)
---@alias WowGetTime         fun(): number
---@alias WowUnitName        fun(unit: WowUnit): string
---@alias WowUnitIsUnit      fun(a: WowUnit, b: WowUnit): boolean
---@alias WowUnitNumber      fun(unit: WowUnit): number
---@alias WowUnitPower       fun(unit: WowUnit, powerType?: integer|string): number
---@alias WowCastingInfo     fun(unit: WowUnit): (string|nil), any, any, (number|nil), (number|nil), (boolean|nil), (number|nil)
---@alias WowChannelInfo     fun(unit: WowUnit): (string|nil), any, any, (number|nil), (number|nil), (number|nil)
---@alias WowThreatSituation fun(unit: WowUnit, target: WowUnit): integer
---@alias WowAuras           fun(unit: WowUnit): table

-- Global function stubs (assign function values; avoids sumneko assign-type warnings)
---@type WowGetTime
GetTime = function() end

---@type WowUnitName
UnitName = function(unit) end

---@type WowUnitIsUnit
UnitIsUnit = function(a, b) end

---@type WowUnitNumber
UnitHealth = function(unit) end

---@type WowUnitNumber
UnitHealthMax = function(unit) end

---@type WowUnitPower
UnitPower = function(unit, powerType) end

---@type WowUnitPower
UnitPowerMax = function(unit, powerType) end

---@type WowCastingInfo
UnitCastingInfo = function(unit) end

---@type WowChannelInfo
UnitChannelInfo = function(unit) end

---@type WowThreatSituation
UnitThreatSituation = function(unit, target) end

---@type WowAuras
UnitAuras = function(unit) end

-- POWER enum table published by wow_api_clone.lua as `_G.POWER`
-- You can also use ---@enum POWER_enum : integer, but class+typed fields is fine too.
---@class POWER_enum
---@field MANA integer
---@field RAGE integer
---@field FOCUS integer
---@field ENERGY integer
---@field COMBO_POINTS integer
---@field RUNES integer
---@field RUNIC_POWER integer
---@field SOUL_SHARDS integer
---@field LUNAR_POWER integer

---@type POWER_enum
POWER = {}  -- stub table for IntelliSense

---@alias WowUnitExists       fun(unit: WowUnit): boolean
---@alias WowUnitGUID         fun(unit: WowUnit): string
---@alias WowUnitDeadGhost    fun(unit: WowUnit): boolean
---@alias WowUnitCanAttack    fun(unit: WowUnit, target: WowUnit): boolean
---@alias WowIsSpellInRange   fun(spell: (number|string), unit: WowUnit): (1|0|nil)
---@alias WowIsUsableSpell    fun(spell: (number|string)): (boolean, boolean)  -- usable, notEnoughMana
---@alias WowGetSpellCooldown fun(spell: (number|string)): (number, number, integer) -- start, duration, enabled
---@alias WowGetSpellCharges  fun(spell: (number|string)): (integer|nil, integer|nil, number|nil, number|nil)
---@alias WowGetTotemInfo     fun(index: integer): (boolean, string, number, number)
---@alias WowGetWeaponEnchant fun(): (boolean, number, integer, integer, boolean, number, integer, integer)
---@alias WowGetInvItemID     fun(unit: WowUnit, slotId: integer): integer
---@alias WowInteractDist     fun(unit: WowUnit, distIndex?: integer): boolean
---@alias WowGetTimePrecise   fun(): number

---@type WowUnitExists
UnitExists = function(unit) end

---@type WowUnitGUID
UnitGUID = function(unit) end

---@type WowUnitDeadGhost
UnitIsDeadOrGhost = function(unit) end

---@type WowUnitCanAttack
UnitCanAttack = function(unit, target) end

---@type WowIsSpellInRange
IsSpellInRange = function(spell, unit) end

---@type WowIsUsableSpell
IsUsableSpell = function(spell) end

---@type WowGetSpellCooldown
GetSpellCooldown = function(spell) end

---@type WowGetSpellCharges
GetSpellCharges = function(spell) end

---@type WowGetTotemInfo
GetTotemInfo = function(index) end

---@type WowGetWeaponEnchant
GetWeaponEnchantInfo = function() end

---@type WowGetInvItemID
GetInventoryItemID = function(unit, slotId) end

---@type WowInteractDist
CheckInteractDistance = function(unit, distIndex) end

---@type WowGetTimePrecise
GetTimePreciseSec = function() end

---@alias WowCastSpell       fun(unit: WowUnit, spell: (number|string), message?: string): boolean
---@alias WowIsKeyDown       fun(key: (integer|string)): boolean
---@alias WowGetTarget       fun(): WowUnit|nil

---@type WowCastSpell
CastSpell = function(unit, spell, message) end

---@type WowIsKeyDown
IsKeyDown = function(key) end

---@type WowGetTarget
GetTarget = function() end

---@alias WowUnitInRange     fun(unit: WowUnit): boolean
---@alias WowGetNumGroup     fun(): integer

---@type WowUnitInRange
UnitInRange = function(unit) end

---@type WowGetNumGroup
GetNumGroupMembers = function() end

---@class C_Timer_table
---@field After fun(delay: number, func: fun())

---@type C_Timer_table
C_Timer = {}
