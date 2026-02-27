local DuoSyncService = {}
DuoSyncService.__index = DuoSyncService

local function safe_now()
    if core and core.time then
        local ok, value = pcall(core.time)
        if ok and tonumber(value) then
            return tonumber(value)
        end
    end
    return os.time()
end

---@class DuoSyncService
function DuoSyncService:new(bb, cfg, logger, bot_id)
    local o = setmetatable({}, DuoSyncService)
    o._bb = bb
    o._cfg = cfg or {}
    o._log = logger
    o._bot_id = tostring(bot_id or "bot")
    o._last_write = 0
    o._json_ok, o._json = pcall(require, "lib/JSON")
    return o
end

function DuoSyncService:_sync_file()
    local sync_cfg = self._cfg.sync or {}
    return tostring(sync_cfg.file or "StrathDuoMage/state/duo_sync.v1.json")
end

function DuoSyncService:_ensure_folder()
    if core and core.create_data_folder then
        core.create_data_folder("StrathDuoMage")
        core.create_data_folder("StrathDuoMage/state")
    end
end

function DuoSyncService:_read_state()
    if not self._json_ok or not self._json or type(self._json.decode) ~= "function" then
        return { schema_version = "duo_sync.v1", peers = {} }
    end

    local path = self:_sync_file()
    local text = nil
    if core and type(core.read_data_file) == "function" then
        text = core.read_data_file(path)
    end
    if (not text or text == "") and io and io.open then
        local f = io.open(path, "r")
        if f then
            text = f:read("*a")
            f:close()
        end
    end

    if not text or text == "" then
        return { schema_version = "duo_sync.v1", peers = {} }
    end

    local data = self._json.decode(text)
    if type(data) ~= "table" then
        return { schema_version = "duo_sync.v1", peers = {} }
    end

    if type(data.peers) ~= "table" then
        data.peers = {}
    end
    return data
end

function DuoSyncService:_write_state(state)
    if not self._json_ok or not self._json or type(self._json.encode) ~= "function" then
        return
    end
    local encoded = self._json.encode(state, true)
    if type(encoded) ~= "string" or encoded == "" then
        return
    end

    local path = self:_sync_file()
    if core and type(core.write_data_file) == "function" and type(core.create_data_file) == "function" then
        core.create_data_file(path)
        core.write_data_file(path, encoded)
        return
    end

    if io and io.open then
        local f = io.open(path, "w")
        if f then
            f:write(encoded)
            f:close()
        end
    end
end

function DuoSyncService:update(now)
    local write_interval = tonumber(self._cfg.sync and self._cfg.sync.write_interval) or 0.20
    if (now - self._last_write) < write_interval then
        return
    end

    self._ensure_folder()

    local state = self:_read_state()
    local peers = state.peers

    peers[self._bot_id] = {
        role = tostring(self._bb:get("duo.role", self._cfg.role or "leader")),
        ts = now,
        in_combat = self._bb:get("player.in_combat", false) == true,
        position = self._bb:get("player.position"),
        target_guid = tostring(self._bb:get("combat.target_guid", "")),
        mana_pct = tonumber(self._bb:get("player.mana_pct", 1.0)) or 1.0,
    }

    state.schema_version = "duo_sync.v1"
    state.updated_at = now
    state.peers = peers
    self:_write_state(state)
    self._last_write = now

    local stale_secs = tonumber(self._cfg.sync and self._cfg.sync.stale_secs) or 2.0
    local partner = nil
    for id, row in pairs(peers) do
        if id ~= self._bot_id and type(row) == "table" then
            local ts = tonumber(row.ts) or 0
            if ts > 0 and (now - ts) <= stale_secs then
                partner = row
                break
            end
        end
    end
    self._bb:set("duo.partner", partner)
end

return DuoSyncService
