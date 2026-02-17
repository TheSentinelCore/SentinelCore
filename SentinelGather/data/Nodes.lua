---@class Nodes
---Database of gatherable node names for herbs and ores
local Nodes = {}

-- Herb patterns organized by expansion
Nodes.HERBS = {
    -- Classic Era (Vanilla)
    "Peacebloom",
    "Silverleaf",
    "Earthroot",
    "Mageroyal",
    "Briarthorn",
    "Stranglekelp",
    "Bruiseweed",
    "Wild Steelbloom",
    "Grave Moss",
    "Kingsblood",
    "Liferoot",
    "Fadeleaf",
    "Goldthorn",
    "Khadgar's Whisker",
    "Wintersbite",
    "Firebloom",
    "Purple Lotus",
    "Arthas' Tears",
    "Sungrass",
    "Blindweed",
    "Ghost Mushroom",
    "Gromsblood",
    "Golden Sansam",
    "Dreamfoil",
    "Mountain Silversage",
    "Sorrowmoss",
    "Plaguebloom",
    "Icecap",
    "Black Lotus",

    -- The Burning Crusade
    "Felweed",
    "Dreaming Glory",
    "Terocone",
    "Ragveil",
    "Flame Cap",
    "Ancient Lichen",
    "Netherbloom",
    "Nightmare Vine",
    "Mana Thistle",
    "Fel Lotus",

    -- Wrath of the Lich King
    "Goldclover",
    "Firethorn",
    "Tiger Lily",
    "Talandra's Rose",
    "Adder's Tongue",
    "Frozen Herb",
    "Lichbloom",
    "Icethorn",
    "Frost Lotus",

    -- Cataclysm
    "Cinderbloom",
    "Stormvine",
    "Azshara's Veil",
    "Heartblossom",
    "Twilight Jasmine",
    "Whiptail",

    -- Mists of Pandaria
    "Green Tea Leaf",
    "Silkweed",
    "Rain Poppy",
    "Snow Lily",
    "Fool's Cap",
    "Golden Lotus",
    "Sha-Touched Herb",

    -- Warlords of Draenor
    "Frostweed",
    "Fireweed",
    "Gorgrond Flytrap",
    "Starflower",
    "Nagrand Arrowbloom",
    "Talador Orchid",

    -- Legion
    "Aethril",
    "Dreamleaf",
    "Foxflower",
    "Fjarnskaggl",
    "Starlight Rose",
    "Felwort",

    -- Battle for Azeroth
    "Riverbud",
    "Star Moss",
    "Akunda's Bite",
    "Winter's Kiss",
    "Siren's Pollen",
    "Anchor Weed",
    "Sea Stalk",

    -- Shadowlands
    "Death Blossom",
    "Rising Glory",
    "Marrowroot",
    "Vigil's Torch",
    "Widowbloom",
    "Nightshade",

    -- Dragonflight
    "Hochenblume",
    "Saxifrage",
    "Bubble Poppy",
    "Writhebark",
    "Lush Hochenblume",
    "Frigid Hochenblume",
    "Windswept Hochenblume",
    "Decayed Hochenblume",
}

-- Ore patterns organized by expansion
Nodes.ORES = {
    -- Classic Era (Vanilla)
    "Copper Vein",
    "Tin Vein",
    "Silver Vein",
    "Iron Deposit",
    "Gold Vein",
    "Mithril Deposit",
    "Truesilver Deposit",
    "Small Thorium Vein",
    "Rich Thorium Vein",
    "Dark Iron Deposit",
    "Ooze Covered Silver Vein",
    "Ooze Covered Gold Vein",
    "Ooze Covered Mithril Deposit",
    "Ooze Covered Truesilver Deposit",
    "Ooze Covered Rich Thorium Vein",

    -- The Burning Crusade
    "Fel Iron Deposit",
    "Adamantite Deposit",
    "Rich Adamantite Deposit",
    "Khorium Vein",
    "Nethercite Deposit",

    -- Wrath of the Lich King
    "Cobalt Deposit",
    "Rich Cobalt Deposit",
    "Saronite Deposit",
    "Rich Saronite Deposit",
    "Titanium Vein",

    -- Cataclysm
    "Obsidium Deposit",
    "Rich Obsidium Deposit",
    "Elementium Vein",
    "Rich Elementium Vein",
    "Pyrite Deposit",
    "Rich Pyrite Deposit",

    -- Mists of Pandaria
    "Ghost Iron Deposit",
    "Rich Ghost Iron Deposit",
    "Kyparite Deposit",
    "Rich Kyparite Deposit",
    "Trillium Vein",
    "Rich Trillium Vein",

    -- Warlords of Draenor
    "True Iron Deposit",
    "Rich True Iron Deposit",
    "Blackrock Deposit",
    "Rich Blackrock Deposit",

    -- Legion
    "Leystone Deposit",
    "Rich Leystone Deposit",
    "Felslate Deposit",
    "Rich Felslate Deposit",
    "Infernal Brimstone",

    -- Battle for Azeroth
    "Monelite Deposit",
    "Rich Monelite Deposit",
    "Storm Silver Deposit",
    "Rich Storm Silver Deposit",
    "Platinum Deposit",
    "Rich Platinum Deposit",
    "Osmenite Deposit",
    "Rich Osmenite Deposit",

    -- Shadowlands
    "Laestrite Deposit",
    "Rich Laestrite Deposit",
    "Solenium Deposit",
    "Rich Solenium Deposit",
    "Oxxein Deposit",
    "Rich Oxxein Deposit",
    "Phaedrum Deposit",
    "Rich Phaedrum Deposit",
    "Sinvyr Deposit",
    "Rich Sinvyr Deposit",
    "Elethium Deposit",
    "Rich Elethium Deposit",

    -- Dragonflight
    "Serevite Deposit",
    "Rich Serevite Deposit",
    "Draconium Deposit",
    "Rich Draconium Deposit",
    "Khaz'gorite Deposit",
    "Rich Khaz'gorite Deposit",
    "Titan-Touched Serevite",
    "Titan-Touched Draconium",
    "Titan-Touched Khaz'gorite",
    "Infurious Serevite",
    "Infurious Draconium",
    "Infurious Khaz'gorite",
}

-- Lookup tables for faster searching (built lazily)
local _herb_lookup = nil
local _ore_lookup = nil

---Build lookup table for herbs
---@return table<string, boolean>
local function get_herb_lookup()
    if not _herb_lookup then
        _herb_lookup = {}
        for _, herb in ipairs(Nodes.HERBS) do
            _herb_lookup[herb:lower()] = true
        end
    end
    return _herb_lookup
end

---Build lookup table for ores
---@return table<string, boolean>
local function get_ore_lookup()
    if not _ore_lookup then
        _ore_lookup = {}
        for _, ore in ipairs(Nodes.ORES) do
            _ore_lookup[ore:lower()] = true
        end
    end
    return _ore_lookup
end

---Check if a name matches any herb pattern
---@param name string The object name to check
---@return boolean is_herb True if matches a herb pattern
function Nodes.is_herb(name)
    if not name or name == "" then
        return false
    end

    local lower_name = name:lower()
    local lookup = get_herb_lookup()

    -- Exact match first
    if lookup[lower_name] then
        return true
    end

    -- Partial match (name contains herb pattern)
    for _, herb in ipairs(Nodes.HERBS) do
        if lower_name:find(herb:lower(), 1, true) then
            return true
        end
    end

    return false
end

---Check if a name matches any ore pattern
---@param name string The object name to check
---@return boolean is_ore True if matches an ore pattern
function Nodes.is_ore(name)
    if not name or name == "" then
        return false
    end

    local lower_name = name:lower()
    local lookup = get_ore_lookup()

    -- Exact match first
    if lookup[lower_name] then
        return true
    end

    -- Partial match (name contains ore pattern)
    for _, ore in ipairs(Nodes.ORES) do
        if lower_name:find(ore:lower(), 1, true) then
            return true
        end
    end

    return false
end

---Get the type of node (herb, ore, or nil)
---@param name string The object name to check
---@return string|nil node_type "herb", "ore", or nil
function Nodes.get_node_type(name)
    if Nodes.is_herb(name) then
        return "herb"
    elseif Nodes.is_ore(name) then
        return "ore"
    end
    return nil
end

---Check if a name matches any node pattern (herb or ore)
---@param name string The object name to check
---@return boolean is_node True if matches any node pattern
---@return string|nil node_type The type if matched
function Nodes.is_node(name)
    local node_type = Nodes.get_node_type(name)
    return node_type ~= nil, node_type
end

---Get all herb patterns
---@return string[]
function Nodes.get_all_herbs()
    return Nodes.HERBS
end

---Get all ore patterns
---@return string[]
function Nodes.get_all_ores()
    return Nodes.ORES
end

---Get total count of known nodes
---@return number herb_count, number ore_count
function Nodes.get_counts()
    return #Nodes.HERBS, #Nodes.ORES
end

---Run unit tests
---@return table<string, boolean> Test results
function Nodes._test()
    local results = {}

    -- Test herb detection
    results.herb_exact = Nodes.is_herb("Peacebloom")
    results.herb_case_insensitive = Nodes.is_herb("PEACEBLOOM")
    results.herb_partial = Nodes.is_herb("Some Peacebloom Node")
    results.herb_negative = not Nodes.is_herb("Copper Vein")
    results.herb_empty = not Nodes.is_herb("")
    results.herb_nil = not Nodes.is_herb(nil)

    -- Test ore detection
    results.ore_exact = Nodes.is_ore("Copper Vein")
    results.ore_case_insensitive = Nodes.is_ore("COPPER VEIN")
    results.ore_partial = Nodes.is_ore("Some Copper Vein Node")
    results.ore_negative = not Nodes.is_ore("Peacebloom")
    results.ore_rich = Nodes.is_ore("Rich Thorium Vein")

    -- Test node type detection
    results.type_herb = (Nodes.get_node_type("Silverleaf") == "herb")
    results.type_ore = (Nodes.get_node_type("Iron Deposit") == "ore")
    results.type_unknown = (Nodes.get_node_type("Random Object") == nil)

    -- Test is_node
    local is_node, node_type = Nodes.is_node("Dreamfoil")
    results.is_node_herb = (is_node and node_type == "herb")

    is_node, node_type = Nodes.is_node("Mithril Deposit")
    results.is_node_ore = (is_node and node_type == "ore")

    is_node, node_type = Nodes.is_node("Not a node")
    results.is_node_false = (not is_node and node_type == nil)

    -- Test counts
    local herb_count, ore_count = Nodes.get_counts()
    results.count_herbs = (herb_count >= 50)
    results.count_ores = (ore_count >= 30)

    return results
end

return Nodes
