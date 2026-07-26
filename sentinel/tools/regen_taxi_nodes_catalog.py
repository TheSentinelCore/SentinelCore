#!/usr/bin/env python3
"""Regenerate sentinel/kernel/catalogs/taxi_nodes.lua from TaxiNodes.dbc.

Provenance mirror of regen_catalog_chain_fixture.py: the DBC is the 2.4.3 client's own
flight-node table; the catalog is committed because the DBC (like the world DB) is not.

Faction columns are determined EMPIRICALLY, not by convention: Stormwind's node exists for
exactly one faction, and whichever MountCreatureID slot is nonzero there is the Alliance slot.
Guessing the order is how a Horde-only node ends up offered to an Alliance character.
"""
import struct, sys, os

DBC = os.path.join(os.path.dirname(__file__), "..", "..",
                   "Emulators", "Mangos - Classic TBC", "extracted", "dbc", "TaxiNodes.dbc")
OUT = os.path.join(os.path.dirname(__file__), "..", "kernel", "catalogs", "taxi_nodes.lua")

def read_dbc(path):
    b = open(path, "rb").read()
    magic, n, fields, rsize, sblock = struct.unpack_from("<4sIIII", b, 0)
    assert magic == b"WDBC", magic
    recs = [struct.unpack_from("<%dI" % fields, b, 20 + i * rsize) for i in range(n)]
    sb = b[20 + n * rsize:]
    def s(off):
        if off == 0 or off >= len(sb): return ""
        return sb[off:sb.index(b"\0", off)].decode("utf-8", "replace")
    return recs, s

def f32(v): return struct.unpack("<f", struct.pack("<I", v))[0]

recs, sread = read_dbc(DBC)
# fmt nifffssssssssssssssssxii = 24 fields: [0]=id [1]=map [2..4]=xyz [5..20]=name_lang x16 [21]=flags [22,23]=mounts
nodes = []
for r in recs:
    name = sread(r[5])
    if not name: continue
    if r[22] == 0 and r[23] == 0:
        # Usable by NEITHER faction: boat/zeppelin pseudo-nodes ("Transport, Menethil Harbor")
        # and hidden markers. Keeping them poisons alias resolution — "menethil harbor" would
        # be ambiguous against a node no character can ever take.
        continue
    nodes.append({
        "id": r[0], "map": r[1],
        "x": f32(r[2]), "y": f32(r[3]), "z": f32(r[4]),
        "name": name, "m0": r[22], "m1": r[23],
    })

sw = next(n for n in nodes if n["name"].startswith("Stormwind"))
assert (sw["m0"] == 0) != (sw["m1"] == 0), "Stormwind must be single-faction: %r" % sw
ALLIANCE_SLOT = "m0" if sw["m0"] != 0 else "m1"
HORDE_SLOT = "m1" if ALLIANCE_SLOT == "m0" else "m0"

def aliases(name):
    out = {name.lower()}
    if "," in name:
        head, tail = [p.strip() for p in name.split(",", 1)]
        out.add(head.lower()); out.add(tail.lower())
    return out

alias_map = {}
for n in nodes:
    for a in aliases(n["name"]):
        alias_map.setdefault(a, []).append(n)

# CLOSED, CURATED colloquial aliases — the spellings the RestedXP corpus actually uses where the
# DBC name differs. Each maps to an EXISTING alias key, so a typo here fails generation instead of
# minting a dangling entry. Additions require a corpus citation; this is an alias table, not a
# fuzzy matcher (the zone-table lesson: a wrong binding is a cross-continent walk, not an error).
CURATED = {
    "un'goro": "marshal's refuge",            # .fly Un'Goro (6) — node: Marshal's Refuge, Un'Goro Crater
    "menethil": "menethil harbor",            # .fly Menethil (4)
    "stormwind city": "stormwind",            # .fly Stormwind City (2)
    "shattrath city": "shattrath",            # .fly Shattrath City (2)
    "darnassus": "rut'theran village",        # .fly Darnassus (4) — Darnassus has no taxi node; Rut'theran serves it
    "teldrassil": "rut'theran village",       # .fly Teldrassil (24) — "Fishing Village" (57) is unused content
    "moonglade": "nighthaven",                # .fly Moonglade (4) — the faction pair of Nighthaven nodes
    "eastern plaguelands": "light's hope chapel",  # (2) — the tower nodes are PvP objectives, not guide stops
    "brackenwall": "brackenwall village",     # (4)
    "spinebreaker": "spinebreaker ridge",     # (1) — the DBC says Ridge; the guides say Post
    "spinebreaker post": "spinebreaker ridge",# (2) — same
    "toshley": "toshley's station",           # (1)
    "shatter": "shatter point",               # (1)
    "sun rock": "sun rock retreat",           # (1)
    "silvermoon": "silvermoon city",          # (2)
    "redridge mountains": "redridge",         # (1) — node: Lakeshire, Redridge
    "arathi highlands": "arathi",             # (4) — Refuge Pointe / Hammerfall faction pair under "arathi"
}
# Node-level pins, for aliases whose candidates share a NAME: "Shatter Point, Hellfire
# Peninsula (Beach Assault)" (148) is the one-off assault event; 149 is the flight master the
# guides mean. Asserted against the node table so a renumbered DBC fails generation.
CURATED_IDS = {
    "shatter point": 149,
    "shatter": 149,
}

for colloquial, canonical in sorted(CURATED.items()):
    assert canonical in alias_map, "curated alias %r -> %r names no DBC alias" % (colloquial, canonical)
    # REPLACE, never append: "teldrassil" curated to Rut'theran must not keep the unused
    # "Fishing Village" candidate it inherited as a zone alias — an appended curation leaves
    # the ambiguity it exists to resolve.
    alias_map[colloquial] = list(alias_map[canonical])
for alias, node_id in sorted(CURATED_IDS.items()):
    hit = [n for n in nodes if n["id"] == node_id]
    assert hit, "curated id %r -> %d names no node" % (alias, node_id)
    alias_map[alias] = hit

lines = []
lines.append("-- kernel/catalogs/taxi_nodes.lua")
lines.append("-- GENERATED by sentinel/tools/regen_taxi_nodes_catalog.py from TaxiNodes.dbc (2.4.3).")
lines.append("-- Do not hand-edit; regenerate. Faction slots were determined empirically against")
lines.append("-- Stormwind (single-faction), not assumed from field order.")
lines.append("--")
lines.append("-- `aliases` maps every lowercase spelling a guide uses -- the full node name, the")
lines.append("-- settlement before the comma, the zone after it -- to a LIST of node ids. A list")
lines.append("-- longer than one is a real ambiguity (two flight masters in one zone); the caller")
lines.append("-- filters by faction and FAILS LOUD if more than one survives. Silent tie-breaking")
lines.append("-- here would fly a character across a continent on a guess.")
lines.append("local M = {}")
lines.append("")
lines.append("M.nodes = {")
for n in sorted(nodes, key=lambda k: k["id"]):
    lines.append('    [%d] = { name = "%s", map = %d, x = %.4f, y = %.4f, z = %.4f, alliance = %s, horde = %s },'
                 % (n["id"], n["name"].replace("\\", "\\\\").replace('"', '\\"'), n["map"], n["x"], n["y"], n["z"],
                    "true" if n[ALLIANCE_SLOT] != 0 else "false",
                    "true" if n[HORDE_SLOT] != 0 else "false"))
lines.append("}")
lines.append("")
lines.append("M.aliases = {")
for a in sorted(alias_map):
    ids = sorted(set(n["id"] for n in alias_map[a]))
    lines.append('    ["%s"] = { %s },' % (a.replace("\\", "\\\\").replace('"', '\\"'), ", ".join(str(i) for i in ids)))
lines.append("}")
lines.append("")
lines.append("""---Resolve a guide destination string to exactly one node id.
---
---Faction-free by default: most destinations are globally unique. When the survivors are exactly
---a faction-complement pair (one Alliance-only, one Horde-only — "arathi" is Refuge Pointe vs
---Hammerfall), the answer depends on who is asking, so `needs_faction` unless a faction was
---given. Anything else plural is a REAL ambiguity ("feralas" has two Alliance nodes) and fails
---loud — a silent tie-break flies the character across a continent on a guess.
---@param dest string
---@param faction string|nil "Alliance" | "Horde" (any casing) | nil
---@return number|nil node_id, string|nil err "unknown_destination" | "ambiguous_destination" | "needs_faction"
function M.resolve(dest, faction)
    if type(dest) ~= "string" then return nil, "unknown_destination" end
    if type(faction) == "string" then faction = faction:lower() end
    local ids = M.aliases[dest:lower():match("^%s*(.-)%s*$")]
    if not ids then return nil, "unknown_destination" end
    local hits = {}
    for _, id in ipairs(ids) do
        local n = M.nodes[id]
        if n and (faction == nil or n[faction]) then hits[#hits + 1] = id end
    end
    if #hits == 1 then return hits[1] end
    if #hits == 0 then return nil, "unknown_destination" end
    if faction == nil and #hits == 2 then
        local a, b = M.nodes[hits[1]], M.nodes[hits[2]]
        local complement = (a.alliance and not a.horde and b.horde and not b.alliance)
            or (b.alliance and not b.horde and a.horde and not a.alliance)
        if complement then return nil, "needs_faction" end
    end
    return nil, "ambiguous_destination"
end

return M""")

open(OUT, "w").write("\n".join(lines) + "\n")
print("wrote %s: %d nodes, %d aliases (alliance slot = %s)" % (OUT, len(nodes), len(alias_map), ALLIANCE_SLOT))
