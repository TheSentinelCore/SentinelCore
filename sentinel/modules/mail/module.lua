-- Mail automation using the Sylvannas core.mail API.

local Settings = require("modules/mail/settings")

local Mail = {}
Mail.__index = Mail

function Mail.new(event_bus, blackboard)
    return setmetatable({
        _event_bus = event_bus,
        _blackboard = blackboard,
        _last_check_time = 0,
        _is_at_mailbox = false,
        _subscriptions = {},
    }, Mail)
end

function Mail:start()
    self._subscriptions[#self._subscriptions + 1] = self._event_bus:subscribe("game:mail_show", function()
        self._is_at_mailbox = true
        self:process_mail()
    end)

    self._subscriptions[#self._subscriptions + 1] = self._event_bus:subscribe("game:mail_closed", function()
        self._is_at_mailbox = false
    end)

    self._subscriptions[#self._subscriptions + 1] = self._event_bus:subscribe("game:mail_inbox_update", function()
        if self._is_at_mailbox then
            self:process_mail()
        end
    end)
end

function Mail:update(blackboard)
    if not self._is_at_mailbox then
        return
    end

    local now_ms = blackboard:get("system.now_ms", 0)
    if now_ms - self._last_check_time >= Settings.MAIL_CHECK_INTERVAL_MS then
        self:process_mail(now_ms)
    end
end

function Mail:process_mail(now_ms)
    if not self._is_at_mailbox or not core or not core.mail then
        return
    end

    now_ms = now_ms or (core.game_time and core.game_time() or 0)
    if now_ms - self._last_check_time < 1000 then
        return
    end
    self._last_check_time = now_ms

    self:_process_inbox()
end

function Mail:_process_inbox()
    core.mail.check_inbox()
    local mail_count = tonumber(core.mail.get_num_inbox_items()) or 0

    for index = mail_count, 1, -1 do
        local header = core.mail.get_inbox_header_info(index)
        if header and (tonumber(header.cod_amount) or 0) <= 0 then
            if Settings.AUTO_TAKE_GOLD and (tonumber(header.money) or 0) > 0 then
                core.mail.take_inbox_money(index)
            end

            if Settings.AUTO_LOOT_ITEMS and (tonumber(header.item_count) or 0) > 0 then
                core.mail.auto_loot_mail_item(index)
            end

            if Settings.AUTO_DELETE_SPAM
                and self:_is_spam(header.subject, header.sender)
                and core.mail.inbox_item_can_delete(index)
            then
                core.mail.delete_inbox_item(index)
            end
        end
    end
end

function Mail:_is_spam(subject, sender)
    local text = string.lower(tostring(subject or "") .. " " .. tostring(sender or ""))
    for _, keyword in ipairs(Settings.SPAM_KEYWORDS) do
        if string.find(text, string.lower(keyword), 1, true) then
            return true
        end
    end
    return false
end

function Mail:send_gold(recipient, copper, subject, body)
    if not core or not core.mail or type(recipient) ~= "string" or recipient == "" then
        return false
    end
    local amount = tonumber(copper) or 0
    local reserve = tonumber(Settings.GOLD_RESERVE) or 0
    if amount <= 0 then
        return false
    end
    local money = core.inventory and core.inventory.get_money and core.inventory.get_money() or nil
    if money and money - amount < reserve then
        return false
    end
    core.mail.set_send_mail_money(amount)
    core.mail.send_mail(recipient, subject or "SentinelCore", body or "")
    return true
end

function Mail:shutdown()
    for _, token in ipairs(self._subscriptions) do
        self._event_bus:unsubscribe(token)
    end
    self._subscriptions = {}
    self._is_at_mailbox = false
end

return Mail
