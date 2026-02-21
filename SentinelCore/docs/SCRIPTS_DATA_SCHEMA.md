# SentinelCore scripts_data Schema (P0 -> P1.5)

## 1. Storage Root
All writable files must stay inside:
- `scripts_data/SentinelCore/`

Directory layout:
```text
scripts_data/
  SentinelCore/
    config/
      vendor_inventory_policy.v1.json
      runtime_profiles.v1.json
    state/
      runtime_state.v1.json
    cache/
      vendor_runtime_cache.v1.json
```

## 2. Design Goals
- Deterministic and versioned.
- Safe for many clients on one machine.
- Small files with clear purpose.
- Separation of user policy vs runtime cache/state.

## 3. `vendor_inventory_policy.v1.json` (User-Owned Policy)
Path:
- `scripts_data/SentinelCore/config/vendor_inventory_policy.v1.json`

Purpose:
- Defines what can/cannot be sold and inventory thresholds.

Schema:
```json
{
  "schema_version": "vendor_inventory_policy.v1",
  "updated_at_unix": 0,
  "min_free_slots": 2,
  "sell_quality_max": 1,
  "repair_enabled": true,
  "sell_gray": true,
  "sell_white": false,
  "sell_green": false,
  "sell_blue": false,
  "sell_epic": false,
  "never_sell": [6948, 17031],
  "always_sell": [1179],
  "keep_stack_min": {
    "17031": 40,
    "17020": 20
  },
  "special_rules": [
    {
      "rule_id": "no_sell_consumables",
      "match": {
        "item_ids": [17031, 17020]
      },
      "action": "keep"
    }
  ]
}
```

Field notes:
- `sell_quality_max`: backward-compatibility fallback threshold for qualities not explicitly mapped by toggles.
- `sell_gray/sell_white/sell_green/sell_blue/sell_epic`: explicit per-quality sell toggles.
- `never_sell`: hard denylist (highest priority).
- `always_sell`: hard allowlist (below `never_sell` priority).
- `keep_stack_min`: minimum stacks to retain for specific item IDs.

Decision priority:
1. `never_sell`
2. explicit `special_rules`
3. `always_sell`
4. quality/global toggles
5. default keep

## 4. `runtime_state.v1.json` (Session/Recovery State)
Path:
- `scripts_data/SentinelCore/state/runtime_state.v1.json`

Purpose:
- Stores crash-safe resumable state and failure counters.

Schema:
```json
{
  "schema_version": "runtime_state.v1",
  "last_session_id": "abc-123",
  "last_state": "paused",
  "last_error_code": "CTX_UNRESOLVED",
  "auto_restart_attempts_used": 1,
  "last_known_context": {
    "canonical_map_id": 530,
    "zone_id": 3518,
    "area_id": 3520,
    "x": -180.1,
    "y": 932.2,
    "z": 54.3
  },
  "last_grind_anchor": {
    "x": -205.0,
    "y": 901.0,
    "z": 52.4
  },
  "updated_at_unix": 0
}
```

## 5. `vendor_runtime_cache.v1.json` (Ephemeral Runtime Intelligence)
Path:
- `scripts_data/SentinelCore/cache/vendor_runtime_cache.v1.json`

Purpose:
- Persists short-lived vendor interaction outcomes to avoid repeated bad choices.

Schema:
```json
{
  "schema_version": "vendor_runtime_cache.v1",
  "entries": [
    {
      "vendor_id": 12345,
      "canonical_map_id": 530,
      "last_result": "interaction_timeout",
      "failure_count": 2,
      "blacklist_until_unix": 0,
      "last_path_cost": 38.4,
      "last_seen_unix": 0
    }
  ],
  "updated_at_unix": 0
}
```

Retention policy:
- prune expired entries each startup.
- cap total entries (for example 500).

## 5.1 `runtime_profiles.v1.json` (Operator Profiles)
Path:
- `scripts_data/SentinelCore/config/runtime_profiles.v1.json`

Purpose:
- Stores named runtime+policy snapshots and active profile selection.

Schema:
```json
{
  "schema_version": "runtime_profiles.v1",
  "active_profile_id": "default",
  "profiles": [
    {
      "profile_id": "default",
      "name": "Default",
      "runtime": {},
      "policy": {},
      "updated_at_unix": 0
    }
  ],
  "updated_at_unix": 0
}
```

## 6. Validation Rules
- Unknown `schema_version` -> fail closed with config error.
- Missing required fields -> load defaults + emit warning (policy file), or fail (state/cache corruption).
- `never_sell` and `always_sell` intersection -> deny by `never_sell`.
- Non-numeric item IDs are rejected.

## 7. Multi-Client Safety
- Single-writer pattern per file.
- Write to temp file then atomic replace.
- Include `updated_at_unix` monotonic check.
- Keep files compact to reduce contention.
