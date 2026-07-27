#!/usr/bin/env python3
"""Regenerate the ZONE catalog and the SPAWN->ZONE index from the extracted client data.

Provenance mirror of regen_taxi_paths_catalog.py: the DBCs and the terrain tiles are the 2.4.3
client's own data, and they are committed nowhere -- the catalogs are, exactly as taxi_nodes.lua
and taxi_paths.{lua,json} are.

WHY THIS EXISTS. `creature` carries map + position and no zone; `creature_zone` is present in the
snapshot and has zero rows. So "what is in this zone" -- the question the Database panel's zone
browser and `GET /zone/{id}/spawns` are built on -- has no answer in SQL alone. It has one in the
client data: the server derives a zone from a position exactly the way mangos does at runtime, and
the derivation is deterministic, so it can be done ONCE here and committed instead of being
recomputed per request against 381 MB of terrain the QueryServer has no business opening.

THREE OUTPUTS, ONE RUN, for the same reason the taxi tool has two: writing them from separate
generators is how the halves of the platform drift apart.
  * kernel/catalogs/zones.lua   -- Sylvannas runtime (no JSON, no io, no load in that sandbox)
  * kernel/catalogs/zones.json  -- the Rust QueryServer, which validates and names zones and
                                   cannot read a Lua table
  * kernel/catalogs/spawn_zones.json -- the spawn->zone index the /zone/{id}/spawns aggregation
                                   joins against

THE DERIVATION, restated from the mangos source in-tree so a reader can check it without reading
C++ (`src/game/Maps/GridMap.cpp`, `src/game/Server/DBCStores.cpp`):

  1. grid tile   gx = int(32 - x/533.33333), gy = int(32 - y/533.33333)  -> maps/%03u%02u%02u.map
     (TerrainInfo::GetGrid)
  2. area BIT    lx = int(16*(32 - x/SIZE)) & 15, ly likewise; area_map[lx*16 + ly]
     (GridMap::getArea). This is the AreaTable *m_AreaBit*, NOT an area id -- confusing them
     silently produces a plausible wrong zone, because both are small integers.
  3. area row    AreaTable.dbc keyed by m_AreaBit (mangos indexes sAreaStore on field 3, which is
     why AreaTableEntryfmt reads "iiin...": the 'n' is at the bit, not at the id).
  4. zone id     entry.ParentAreaID or, when that is 0, the area's own id
     (TerrainManager::GetZoneIdByAreaFlag).

  The fallback in step 3 is not defensive padding: instance maps ship no terrain tiles at all
  (Blackrock Depths, Dire Maul, Maraudon and 30 others are WMO interiors), so the grid lookup finds
  no file and mangos falls back to Map.dbc's m_areaTableID for the whole map. Without it 8,556
  creature spawns -- every instance in the game -- resolve to nothing.

WHAT IS DELIBERATELY NOT EMITTED. A per-GUID zone map. 109,352 rows of it would be committed data
whose only consumer aggregates it away immediately; the endpoint's unit of answer is
(zone, entry, count), so that is what is stored. Positions are already served, per entry, by
`GET /spawns/{type}/{entry}` and, per radius, by `GET /spawns/nearby`.

Usage:
    python3 sentinel/tools/regen_zone_catalog.py
    SENTINEL_EXTRACTED=/path/to/extracted SENTINEL_DB=/path/to/tbcmangos.sqlite \\
        python3 sentinel/tools/regen_zone_catalog.py

Both inputs are gitignored, so both are overridable: a git worktree has the source tree and
neither the 381 MB extract nor the world DB.
"""
import collections
import json
import os
import sqlite3
import struct
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))

EXTRACTED = os.environ.get(
    "SENTINEL_EXTRACTED",
    os.path.join(ROOT, "Emulators", "Mangos - Classic TBC", "extracted"),
)
DB_PATH = os.environ.get("SENTINEL_DB", os.path.join(ROOT, "tbcmangos.sqlite"))

AREA_DBC = os.path.join(EXTRACTED, "dbc", "AreaTable.dbc")
MAP_DBC = os.path.join(EXTRACTED, "dbc", "Map.dbc")
MAPS_DIR = os.path.join(EXTRACTED, "maps")

CATALOGS = os.path.join(ROOT, "sentinel", "kernel", "catalogs")
OUT_LUA = os.path.join(CATALOGS, "zones.lua")
OUT_JSON = os.path.join(CATALOGS, "zones.json")
OUT_SPAWNS = os.path.join(CATALOGS, "spawn_zones.json")

SOURCE = "AreaTable.dbc + Map.dbc + maps/*.map (2.4.3, Mangos Classic TBC extract)"
GENERATOR = "sentinel/tools/regen_zone_catalog.py"

#: mangos SIZE_OF_GRIDS (src/game/Maps/GridDefines.h). Every coordinate conversion below is in
#: these units; a rounded 533.0 shifts tile boundaries by metres and misfiles border spawns.
SIZE_OF_GRIDS = 533.33333

#: GridMapAreaHeader.flags bit meaning "this tile has no per-cell area grid, use gridArea for all
#: of it" (MAP_AREA_NO_AREA, src/game/Maps/GridMapDefines.h).
MAP_AREA_NO_AREA = 0x0001


def read_dbc(path):
    """A WDBC file as (records, string_reader), identical to the taxi tools' reader."""
    with open(path, "rb") as fh:
        b = fh.read()
    magic, n, fields, rsize, _sblock = struct.unpack_from("<4sIIII", b, 0)
    assert magic == b"WDBC", "%s is not a WDBC file: %r" % (path, magic)
    recs = [struct.unpack_from("<%dI" % fields, b, 20 + i * rsize) for i in range(n)]
    sb = b[20 + n * rsize:]

    def s(off):
        if off == 0 or off >= len(sb):
            return ""
        return sb[off:sb.index(b"\0", off)].decode("utf-8", "replace")

    return recs, s


def load_areas():
    """`AreaTable.dbc` as (by_id, by_area_bit).

    Field indices come from mangos `AreaTableEntryfmt` = "iiinixxxxxissssssssssssssssxiiiiixx":
    0 m_ID, 1 m_ContinentID, 2 m_ParentAreaID, 3 m_AreaBit, 10 m_ExplorationLevel, 11 enUS name.

    `m_ExplorationLevel` is kept under its own name because it is NOT a zone level: the client
    awards exploration XP per sub-area, so 705 of the 1,643 rows -- including every starting zone
    -- carry 0. A field called `level` here would render "Elwynn Forest, level 0" in a panel.
    """
    recs, sread = read_dbc(AREA_DBC)
    by_id, by_bit = {}, {}
    for r in recs:
        area = {
            "id": r[0],
            "map": r[1],
            "parent": r[2],
            "bit": r[3],
            "exploration_level": r[10],
            "name": sread(r[11]),
        }
        by_id[area["id"]] = area
        # The DBC store mangos builds is keyed by the bit, so the bit is unique by construction.
        # Assert it rather than trust it: a duplicate would mean the fmt string was misread and
        # every zone below it would be silently attributed to the wrong area.
        assert area["bit"] not in by_bit, "duplicate m_AreaBit %d" % area["bit"]
        by_bit[area["bit"]] = area
    return by_id, by_bit


def load_map_zones():
    """`Map.dbc` map id -> m_areaTableID (mangos MapEntry.linked_zone, field 27).

    This is the zone every position on an instance map belongs to, and it is the ONLY zone answer
    for maps that ship no terrain tiles.
    """
    recs, _ = read_dbc(MAP_DBC)
    return {r[0]: r[27] for r in recs}


class Terrain:
    """The area-bit grids, read lazily and cached per tile (1,497 of the 3,586 are ever touched)."""

    def __init__(self, maps_dir):
        self._dir = maps_dir
        self._tiles = {}
        self.tiles_read = 0

    def _tile(self, mapid, gx, gy):
        key = (mapid, gx, gy)
        if key in self._tiles:
            return self._tiles[key]
        path = os.path.join(self._dir, "%03u%02u%02u.map" % (mapid, gx, gy))
        tile = None
        if os.path.exists(path):
            with open(path, "rb") as fh:
                b = fh.read()
            magic, _ver, area_off, _area_size = struct.unpack_from("<4sIII", b, 0)
            assert magic == b"MAPS", "%s is not a mangos map tile: %r" % (path, magic)
            fourcc, flags, grid_area = struct.unpack_from("<4sHH", b, area_off)
            assert fourcc == b"AREA", "%s has no AREA block: %r" % (path, fourcc)
            if flags & MAP_AREA_NO_AREA:
                tile = ("flat", grid_area)
            else:
                tile = ("grid", struct.unpack_from("<256H", b, area_off + 8))
            self.tiles_read += 1
        self._tiles[key] = tile
        return tile

    def area_bit(self, mapid, x, y):
        """`GridMap::getArea`. `None` when no tile covers the position, `0` when the tile has no
        area bit there -- two different facts, and both fall through to the Map.dbc zone."""
        gx = int(32 - x / SIZE_OF_GRIDS)
        gy = int(32 - y / SIZE_OF_GRIDS)
        if not (0 <= gx < 64 and 0 <= gy < 64):
            return None
        tile = self._tile(mapid, gx, gy)
        if tile is None:
            return None
        if tile[0] == "flat":
            return tile[1]
        lx = int(16 * (32 - x / SIZE_OF_GRIDS)) & 15
        ly = int(16 * (32 - y / SIZE_OF_GRIDS)) & 15
        return tile[1][lx * 16 + ly]


def make_zone_resolver(areas_by_id, areas_by_bit, map_zones, terrain):
    def zone_of(mapid, x, y):
        bit = terrain.area_bit(mapid, x, y)
        area = areas_by_bit.get(bit) if bit else None
        if area is None:
            area = areas_by_id.get(map_zones.get(mapid, 0))
        if area is None:
            return None
        return area["parent"] or area["id"]

    return zone_of


def index_spawns(con, table, zone_of):
    """{zone_id: {entry: spawn_count}} plus the per-map tally of what did not resolve."""
    by_zone = collections.defaultdict(collections.Counter)
    unresolved = collections.Counter()
    total = 0
    sql = "SELECT map, position_x, position_y, id FROM %s" % table
    for mapid, x, y, entry in con.execute(sql):
        total += 1
        zone = zone_of(mapid, x, y)
        if zone:
            by_zone[zone][entry] += 1
        else:
            unresolved[mapid] += 1
    return by_zone, unresolved, total


def dense_map(counter):
    """`{"299":29,"721":264}` on ONE line.

    A committed generated file is only reviewable if a diff reads as a change; pretty-printing
    109k counts across 30,000 lines makes every regeneration a wall of noise, while one line per
    zone makes "Elwynn Forest gained a spawn" a one-line diff.
    """
    return "{" + ",".join('"%d":%d' % kv for kv in sorted(counter.items())) + "}"


def write_spawn_index(path, creatures, objects, unresolved, totals):
    lines = ['{']
    lines.append('  "source": %s,' % json.dumps(SOURCE))
    lines.append('  "generated_by": %s,' % json.dumps(GENERATOR))
    lines.append('  "totals": %s,' % json.dumps(totals, sort_keys=True))
    lines.append('  "unresolved_by_map": %s,' % json.dumps(unresolved, sort_keys=True))
    for name, index in (("creatures", creatures), ("objects", objects)):
        lines.append('  "%s": {' % name)
        rows = ['    "%d": %s' % (z, dense_map(index[z])) for z in sorted(index)]
        lines.append(",\n".join(rows))
        lines.append("  }," if name == "creatures" else "  }")
    lines.append("}")
    with open(path, "w") as fh:
        fh.write("\n".join(lines) + "\n")


def write_zones_json(path, areas_by_id, map_zones):
    """One line per area, for the same diff-reviewability reason as `dense_map`."""
    rows = [
        '    {"id":%d,"name":%s,"map":%d,"parent":%d,"exploration_level":%d}'
        % (a["id"], json.dumps(a["name"]), a["map"], a["parent"], a["exploration_level"])
        for a in sorted(areas_by_id.values(), key=lambda a: a["id"])
    ]
    map_row = ",".join(
        '"%d":%d' % (m, z) for m, z in sorted(map_zones.items()) if z
    )
    lines = [
        "{",
        '  "source": %s,' % json.dumps(SOURCE),
        '  "generated_by": %s,' % json.dumps(GENERATOR),
        '  "map_zones": {%s},' % map_row,
        '  "areas": [',
        ",\n".join(rows),
        "  ]",
        "}",
    ]
    with open(path, "w") as fh:
        fh.write("\n".join(lines) + "\n")


LUA_TAIL = '''
---The display name for an area or zone id, or "" when the catalog has no such id.
---
---Empty rather than nil so a panel can concatenate the result without a guard: an unknown id is
---an ordinary answer here (`quest_template.ZoneOrSort` overloads the column with sort buckets),
---not a defect worth raising over.
---@param id number|nil area or zone id
---@return string
function M.name(id)
    local area = type(id) == "number" and M.areas[id] or nil
    return area and area.name or ""
end

---The ZONE an area belongs to -- itself when the area IS a zone.
---
---`parent` is AreaTable's m_ParentAreaID: 0 means top level. Northshire Valley (9) answers 12,
---Elwynn Forest, which is the id the spawn index and the zone browser are keyed by.
---@param id number|nil area id
---@return number|nil
function M.zone_of(id)
    local area = type(id) == "number" and M.areas[id] or nil
    if not area then return nil end
    if area.parent ~= 0 then return area.parent end
    return id
end

---Every top-level zone id, ascending. Zones only -- sub-areas are in `M.areas` and are not
---browsable destinations.
---@return number[]
function M.zone_ids()
    return M._zone_ids
end

---Case-insensitive exact name lookup, zones preferred over sub-areas.
---
---Names are not unique (4095 and 4131 are both "Magisters' Terrace", the outdoor area and the
---instance), so this answers with the zone when one carries the name and the lowest id otherwise
---rather than with whichever row the hash walk reached first.
---@param name string|nil
---@return number|nil
function M.resolve(name)
    if type(name) ~= "string" then return nil end
    return M._by_name[name:lower()]
end

return M'''


def write_zones_lua(path, areas_by_id):
    zone_ids = sorted(a["id"] for a in areas_by_id.values() if a["parent"] == 0)

    # Zones win ties, then the lowest id. Built here rather than in Lua so the runtime pays
    # nothing at require time and the tie-break is visible in the committed bytes.
    by_name = {}
    for area in sorted(areas_by_id.values(), key=lambda a: (a["parent"] != 0, a["id"])):
        key = area["name"].lower()
        if area["name"] and key not in by_name:
            by_name[key] = area["id"]

    out = [
        "-- kernel/catalogs/zones.lua",
        "-- GENERATED by %s from AreaTable.dbc (2.4.3)." % GENERATOR,
        "-- Do not hand-edit; regenerate. zones.json is the same table for the Rust QueryServer and",
        "-- is written by the same run -- patching one alone splits the platform.",
        "--",
        "-- Every AreaTable row, not only the %d top-level zones: quest and spawn data name" % len(zone_ids),
        "-- SUB-areas as often as zones (quest 54 sits in Northshire Valley, 9, not Elwynn Forest,",
        "-- 12), so a zones-only table would answer \"\" for a third of the game's content.",
        "--",
        "-- `parent` is m_ParentAreaID; 0 marks a top-level zone. M.zone_of collapses an area to its",
        "-- zone, which is the id kernel/catalogs/spawn_zones.json and GET /zone/{id}/spawns key on.",
        "local M = {}",
        "",
        "M.areas = {",
    ]
    for area in sorted(areas_by_id.values(), key=lambda a: a["id"]):
        out.append(
            '    [%d] = { name = %s, map = %d, parent = %d, exploration_level = %d },'
            % (area["id"], lua_string(area["name"]), area["map"], area["parent"],
               area["exploration_level"])
        )
    out.append("}")
    out.append("")
    out.append("--- Top-level zone ids (parent == 0), ascending.")
    out.append("M._zone_ids = {")
    for chunk in range(0, len(zone_ids), 12):
        out.append("    " + " ".join("%d," % i for i in zone_ids[chunk:chunk + 12]))
    out.append("}")
    out.append("")
    out.append("--- Lowercased name -> id, zones preferred over sub-areas on a tie.")
    out.append("M._by_name = {")
    for key in sorted(by_name):
        out.append("    [%s] = %d," % (lua_string(key), by_name[key]))
    out.append("}")
    out.append(LUA_TAIL)
    with open(path, "w") as fh:
        fh.write("\n".join(out) + "\n")


def lua_string(s):
    return '"%s"' % s.replace("\\", "\\\\").replace('"', '\\"')


def main():
    for path in (AREA_DBC, MAP_DBC, MAPS_DIR, DB_PATH):
        if not os.path.exists(path):
            sys.exit(
                "missing input: %s\n"
                "The extract and the world DB are gitignored; set SENTINEL_EXTRACTED / SENTINEL_DB."
                % path
            )

    areas_by_id, areas_by_bit = load_areas()
    map_zones = load_map_zones()
    terrain = Terrain(MAPS_DIR)
    zone_of = make_zone_resolver(areas_by_id, areas_by_bit, map_zones, terrain)

    con = sqlite3.connect("file:%s?mode=ro" % DB_PATH, uri=True)
    creatures, creature_bad, creature_total = index_spawns(con, "creature", zone_of)
    objects, object_bad, object_total = index_spawns(con, "gameobject", zone_of)

    # A regression in the derivation shows up here first and shows up big: 8% unresolved was the
    # symptom of the missing instance fallback. Anything past a rounding-error fraction means the
    # tile format, the bit index, or the fallback changed meaning.
    for label, bad, total in (
        ("creature", sum(creature_bad.values()), creature_total),
        ("gameobject", sum(object_bad.values()), object_total),
    ):
        assert bad * 1000 <= total, (
            "%d of %d %s spawns resolved to no zone (>0.1%%) -- the derivation regressed"
            % (bad, total, label)
        )

    totals = {
        "creature_spawns": creature_total,
        "creature_unresolved": sum(creature_bad.values()),
        "gameobject_spawns": object_total,
        "gameobject_unresolved": sum(object_bad.values()),
        "areas": len(areas_by_id),
        "zones_with_creatures": len(creatures),
    }
    write_zones_json(OUT_JSON, areas_by_id, map_zones)
    write_zones_lua(OUT_LUA, areas_by_id)
    write_spawn_index(
        OUT_SPAWNS,
        creatures,
        objects,
        {"creatures": dict(creature_bad), "objects": dict(object_bad)},
        totals,
    )

    print(
        "wrote %s, %s and %s\n"
        "  %d areas (%d top-level zones), %d map tiles read\n"
        "  %d creature spawns -> %d zones (%d unresolved)\n"
        "  %d gameobject spawns -> %d zones (%d unresolved)"
        % (
            OUT_LUA, OUT_JSON, OUT_SPAWNS,
            len(areas_by_id), sum(1 for a in areas_by_id.values() if a["parent"] == 0),
            terrain.tiles_read,
            creature_total, len(creatures), sum(creature_bad.values()),
            object_total, len(objects), sum(object_bad.values()),
        )
    )


if __name__ == "__main__":
    main()
