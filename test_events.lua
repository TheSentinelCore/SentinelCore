package.path = './sentinel/?.lua;' .. package.path
local Engine = require('modules/quest/engine')
local Events = require('modules/quest/events')
local JSON = require('lib/JSON')

local core = {log = print, logError = print}
_G.core = core

local bb = {data={}, get = function(t,k) return t.data[k] end, set = function(t,k,v) t.data[k]=v end}
bb.data['system.now_ms'] = 0
bb.data['player.level'] = 1
bb.data['player.faction'] = 'Alliance'
bb.data['player.position'] = {x=0,y=0,z=0}
bb.data['system.map_id'] = 0
bb.data['system.zone_name'] = 'Test Zone'
bb.data['module.quest.quests'] = {}

local eventBus = {subscribe = function() end, publish = function(e,p) print('EVENT:', e, JSON.encode(p)) end}

local engine = Engine.new(bb, eventBus)
print('Engine created')

-- Test quest acceptance
engine._blackboard.data['module.quest.quests'] = { [783] = {title='Test Quest', level=1, is_complete=false, objectives={{current=0,required=8}}} }
engine:updateEvents()
print('---')

-- Test quest completion
engine._blackboard.data['module.quest.quests'][783].objectives[1].current = 8
engine._blackboard.data['module.quest.quests'][783].is_complete = true
engine:updateEvents()
print('---')

-- Test quest turn in
engine._blackboard.data['module.quest.quests'] = {}
engine:updateEvents()
print('All event tests passed')