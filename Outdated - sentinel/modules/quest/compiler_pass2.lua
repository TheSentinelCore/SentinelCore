-- sentinel/modules/quest/compiler_pass2.lua
-- Compiler Pass 2: Implied Action Insertion
-- Inserts implied actions based on semantic analysis after DB resolution.
--
-- Design: the pass is provider-injected. A `quest_data` provider supplies quest
-- templates, quest<NPC> relations and travel times. In production this is wired
-- to QuestData/QuestRegistry (which talk to the Mangos DB via QueryClient); in
-- tests/offline it is a lightweight mock. This keeps the compiler deterministic
-- and testable without a live database connection.

local SourceAST = require("modules/quest/source_ast")

local CompilerPass2 = {}
CompilerPass2.__index = CompilerPass2

-- Default no-op provider: returns nil for everything, so no implied actions are
-- inserted. Production code must inject a real provider.
local function default_provider()
  local p = {}
  function p:getQuest(_) return nil end
  function p:getQuestNPCs(_, _) return nil end
  function p:getTravelTime(_, _, _) return nil end
  return p
end

function CompilerPass2.new(provider, config)
  return setmetatable({
    _provider = provider or default_provider(),
    _config = config or {
      repair_durability_threshold = 0.5, -- insert Repair guarded by avgDurability < this
      default_travel_wait_s = 30,        -- fallback wait if no travel-time lookup
    },
  }, CompilerPass2)
end

--- Run the Level 2 pass on the AST
--- @param ast table The AST after Level 1 processing
--- @return table {ok=true, ast=AST, errors={}} or {ok=false, errors={string}}
function CompilerPass2:run(ast)
  local errors = {}

  for op_name, op in pairs(ast.operations) do
    local op_errs = self:process_operation(op)
    for _, err in ipairs(op_errs) do
      table.insert(errors, string.format("Operation '%s': %s", op_name, err))
    end
  end

  for bp_name, bp in pairs(ast.blueprints) do
    local bp_errs = self:process_blueprint(bp)
    for _, err in ipairs(bp_errs) do
      table.insert(errors, string.format("Blueprint '%s': %s", bp_name, err))
    end
  end

  if #errors > 0 then
    return { ok = false, errors = errors }
  end
  return { ok = true, ast = ast, errors = {} }
end

--- Process an operation node, inserting implied actions where needed.
--- Builds a fresh action list (never mutates the list while iterating it).
--- @param op table OperationAST node
--- @return table array of error strings
function CompilerPass2:process_operation(op)
  local errors = {}
  if op == nil then
    return { "process_operation called with a nil operation node" }
  end

  local actions = op.actions
  if type(actions) ~= "table" then
    -- Nothing to process; do not crash on a missing actions list.
    return errors
  end

  local new_actions = {}
  for i = 1, #actions do
    local action = actions[i]
    if action ~= nil then
      table.insert(new_actions, action)
      local implied = self:get_implied_actions_after_action(op, action, i)
      for _, ia in ipairs(implied) do
        if not self:_has_similar(new_actions, ia) then
          table.insert(new_actions, ia)
        end
      end
    end
  end

  -- User-authored actions win: drop any implied action that duplicates an
  -- equivalent user-placed action.
  op.actions = self:_remove_redundant_implied(new_actions)
  return errors
end

--- Process a blueprint node, inserting implied actions where needed.
--- @param bp table BlueprintAST node
--- @return table array of error strings
function CompilerPass2:process_blueprint(bp)
  local errors = {}
  if bp == nil then
    return { "process_blueprint called with a nil blueprint node" }
  end

  local items = bp.expands_to
  if type(items) ~= "table" then
    return errors
  end

  local new_items = {}
  for i = 1, #items do
    local item = items[i]
    if item ~= nil then
      table.insert(new_items, item)
      local implied = self:get_implied_actions_after_action(bp, item, i)
      for _, ia in ipairs(implied) do
        if not self:_has_similar(new_items, ia) then
          table.insert(new_items, ia)
        end
      end
    end
  end

  bp.expands_to = self:_remove_redundant_implied(new_items)
  return errors
end

--- Get implied actions that should be inserted after a given action.
--- @param parent table The parent node (operation or blueprint)
--- @param action table The action to check for implied actions after
--- @param index number The index of the action in the parent's action list
--- @return table Array of implied action AST nodes to insert
function CompilerPass2:get_implied_actions_after_action(parent, action, index)
  local implied = {}
  local atype = action.action_type or action.type

  if atype == "KillCreature" or atype == "KillTarget" then
    self:_append(implied, self:get_implied_loot_after_kill(parent, action))
  elseif atype == "AcceptQuest" or atype == "PickupQuest" then
    self:_append(implied, self:get_implied_turnin_after_accept(parent, action))
  elseif atype == "Vendor" then
    self:_append(implied, self:get_implied_repair_after_vendor(parent, action))
  elseif atype == "TravelTo" or atype == "Travel" then
    self:_append(implied, self:get_implied_wait_after_travel(parent, action))
  end

  -- Heuristic 5: looting enabled but nothing expected -> consider Fish.
  self:_append(implied, self:get_implied_fish_if_looting(parent, action, index))

  return implied
end

--- Implied Loot after a Kill: for each required quest item, insert a Loot action.
function CompilerPass2:get_implied_loot_after_kill(parent, action)
  local implied = {}
  local args = action.args or {}
  local quest_id = args.quest_id
  if quest_id == nil then
    return implied
  end

  local quest = self._provider:getQuest(quest_id)
  if not quest then
    return implied
  end

  -- Mangos quest_template uses ReqItemId1..6 / ReqItemCount1..6.
  for i = 1, 6 do
    local item_id = quest["ReqItemId" .. i]
    local count = quest["ReqItemCount" .. i] or 1
    if item_id and item_id > 0 then
      table.insert(implied, self:create_action("Loot", {
        item_id = item_id,
        count = count,
        creature_id = args.creature_name_id or args.creature_id,
        quest_id = quest_id,
      }, { generated_by = "level2_implied", source = "kill_requires_item" }))
    end
  end
  return implied
end

--- Implied TurnIn after Accept/Pickup: auto-complete quests turn in immediately.
function CompilerPass2:get_implied_turnin_after_accept(parent, action)
  local implied = {}
  local args = action.args or {}
  local quest_id = args.quest_id
  if quest_id == nil then
    return implied
  end

  local quest = self._provider:getQuest(quest_id)
  if not quest then
    return implied
  end

  -- Mangos quest_template.Method == 1 means the quest auto-completes on accept
  -- (you accept and immediately turn in at the same NPC).
  if quest.Method == 1 then
    local npcs = self._provider:getQuestNPCs(quest_id, "turnin")
      or self._provider:getQuestNPCs(quest_id, "giver")
    local npc = npcs and npcs[1]
    table.insert(implied, self:create_action("TurnIn", {
      quest_id = quest_id,
      npc_id = npc and npc.id,
      npc_name = npc and npc.name,
      auto_complete = true,
    }, { generated_by = "level2_implied", source = "auto_complete_quest" }))
  end
  return implied
end

--- Implied Repair after Vendor: insert a Repair guarded by a durability threshold.
function CompilerPass2:get_implied_repair_after_vendor(parent, action)
  local implied = {}
  local threshold = self._config.repair_durability_threshold or 0.5
  local condition = string.format("player.avgDurability < %s", threshold)
  table.insert(implied, self:create_action("Repair", {
    durability_threshold = threshold,
  }, { generated_by = "level2_implied", source = "vendor_durability" }, condition))
  return implied
end

--- Implied Wait after Travel: flight/zeppelin/boat travel has a wait time.
function CompilerPass2:get_implied_wait_after_travel(parent, action)
  local implied = {}
  local args = action.args or {}
  local method = args.method or "walk"
  if method == "walk" then
    -- Walking has no discrete boarding wait; nothing to insert.
    return implied
  end

  local duration = self._provider:getTravelTime(args.from, args.to, method)
  if not duration or duration <= 0 then
    duration = self._config.default_travel_wait_s or 30
  end

  table.insert(implied, self:create_action("Wait", {
    duration_s = duration,
    reason = "travel:" .. tostring(method),
  }, { generated_by = "level2_implied", source = "travel_wait" }))
  return implied
end

--- Heuristic 5: if looting is enabled but no loot/collect/fish is expected,
--- consider inserting a Fish action. Triggered by an `allow_fish` flag on an
--- action, or a `loot_enabled` flag on the parent, when no loot-like action
--- exists anywhere in the parent's list.
function CompilerPass2:get_implied_fish_if_looting(parent, action, index)
  local action_args = action.args or {}
  local parent_loot_enabled = parent and parent.loot_enabled == true
  if not (action_args.allow_fish == true or parent_loot_enabled) then
    return {}
  end

  local list = parent and (parent.actions or parent.expands_to) or {}
  for j = index, #list do
    local a = list[j]
    if a then
      local at = a.action_type or a.type
      if at == "Loot" or at == "CollectItem" or at == "Fish" then
        -- Something already covers looting; do not insert Fish.
        return {}
      end
    end
  end

  return {
    self:create_action("Fish", {
      reason = "loot_enabled_no_expected",
    }, { generated_by = "level2_implied", source = "fish_heuristic" }),
  }
end

--- Create an implied action AST node, always marked as compiler-generated.
--- @param action_type string The kind of action (e.g., "Loot", "TurnIn", "Wait", "Repair", "Fish")
--- @param args table The arguments for the action
--- @param _debug table Debug metadata (merged with generated_by marker)
--- @param condition string|nil Optional guard expression
--- @return table Action node (carries both `type` and `action_type` for compatibility)
function CompilerPass2:create_action(action_type, args, _debug, condition)
  local dbg = _debug or {}
  dbg.generated_by = "level2_implied"
  return {
    type = action_type,
    action_type = action_type,
    id = nil,
    args = args or {},
    condition = condition,
    _debug = dbg,
  }
end

-- Internal helpers -----------------------------------------------------------

function CompilerPass2:_append(dst, src)
  for _, a in ipairs(src) do
    dst[#dst + 1] = a
  end
end

--- A short signature used to detect duplicate implied actions.
function CompilerPass2:_signature(action)
  local atype = action.action_type or action.type
  local args = action.args or {}
  if atype == "Loot" then
    return "Loot:" .. tostring(args.item_id)
  elseif atype == "TurnIn" then
    return "TurnIn:" .. tostring(args.quest_id)
  elseif atype == "Repair" then
    return "Repair"
  elseif atype == "Wait" then
    return "Wait:" .. tostring(args.reason)
  elseif atype == "Fish" then
    return "Fish:" .. tostring(args.reason)
  end
  return nil
end

function CompilerPass2:_has_similar(list, candidate)
  local sig = self:_signature(candidate)
  if sig == nil then
    return false
  end
  for _, existing in ipairs(list) do
    if self:_signature(existing) == sig then
      return true
    end
  end
  return false
end

function CompilerPass2:_is_generated(action)
  return action and action._debug and action._debug.generated_by == "level2_implied"
end

--- Drop implied actions that duplicate an equivalent user-authored action.
--- User intent always wins over the compiler's convenience insertions.
function CompilerPass2:_remove_redundant_implied(list)
  local user_sigs = {}
  for _, a in ipairs(list) do
    if not self:_is_generated(a) then
      local s = self:_signature(a)
      if s then user_sigs[s] = true end
    end
  end

  local out = {}
  for _, a in ipairs(list) do
    if self:_is_generated(a) and user_sigs[self:_signature(a)] then
      -- Equivalent user action exists; drop the implied one.
    else
      out[#out + 1] = a
    end
  end
  return out
end

return CompilerPass2
