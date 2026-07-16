-- Mail Automation Settings
-- Configure automatic mail processing behavior

local Settings = {}

-- Mail checking behavior
Settings.MAIL_CHECK_INTERVAL_MS = 30000  -- How often to check mail when near mailbox (ms)
Settings.AUTO_TAKE_GOLD = true           -- Automatically take gold from mail
Settings.AUTO_LOOT_ITEMS = true          -- Automatically take items from mail
Settings.AUTO_DELETE_SPAM = true         -- Automatically delete suspected spam mail

-- Auto-send to alt behavior
Settings.ALT_NAME = ""                   -- Character name to send items to (empty = disabled)
Settings.SEND_QUALITY_THRESHOLD = 2      -- Minimum item quality to send to alt (0=poor,1=common,2=uncommon,3=rare,4=epic,5=legendary,6=artifact)
Settings.KEEP_QUEST_ITEMS = true         -- Never send quest items to alt
Settings.GOLD_RESERVE = 1000             -- Minimum gold to keep (in copper) when sending mail

-- Spam detection keywords (case insensitive)
Settings.SPAM_KEYWORDS = {
    "gold",
    "cheap",
    "best price",
    "discount",
    "sale",
    "powerleveling",
    "wowgold",
    "gold farming"
}

return Settings