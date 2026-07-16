local VendorAdapters = {}

-- Navigation Adapter Interface
---@class NavigationAdapter
---@field move_to fun(destination: table, opts?: table): boolean
---@field stop fun(reason: string): boolean
---@field is_active fun(): boolean

-- Interaction Adapter Interface
---@class InteractionAdapter
---@field find_npc fun(npc_id: number): table|nil
---@field target_npc fun(npc: table): boolean
---@field interact_with_npc fun(npc: table): boolean
---@field is_vendor_window_open fun(): boolean
---@field close_vendor fun(): boolean

-- Transaction Adapter Interface
---@class TransactionAdapter
---@field get_vendor_item_count fun(): number|nil
---@field get_vendor_item_info fun(index: number): table|nil
---@field find_vendor_slot fun(item_id: number): number|nil
---@field buy_item fun(slot: number, count: number): boolean
---@field repair_all_items fun(guild_bank: boolean): boolean
---@field sell_item fun(bag: number, slot: number): boolean
---@field use_container_item fun(bag: number, slot: number): boolean

-- Inventory Adapter Interface
---@class InventoryAdapter
---@field get_free_bag_slots fun(): number
---@field get_item_count fun(item_id: number): number
---@field for_each_item fun(callback: function): void
---@field get_item_quality fun(item_id: number): number|nil

-- Quality Service Adapter Interface
---@class QualityServiceAdapter
---@field fetch_qualities fun(item_ids: number[], callback: function(code: number, response: string)): void

VendorAdapters.NavigationAdapter = {}
VendorAdapters.InteractionAdapter = {}
VendorAdapters.TransactionAdapter = {}
VendorAdapters.InventoryAdapter = {}
VendorAdapters.QualityServiceAdapter = {}

return VendorAdapters