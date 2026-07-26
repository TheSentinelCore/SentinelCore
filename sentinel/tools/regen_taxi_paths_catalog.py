#!/usr/bin/env python3
"""Regenerate the flight-ROUTE catalog from TaxiPath.dbc, as Lua and as JSON.

Provenance mirror of regen_taxi_nodes_catalog.py: the DBC is the 2.4.3 client's own flight-path
table; the catalogs are committed because the DBC (like the world DB) is not. Sibling of that
tool -- it answers "does this flight master exist", this one answers "are two flight masters
actually connected, and for how much". Without the second answer a questing.Flight task can
compile a plan that lands the character at a flight master with no route onward.

TWO OUTPUTS, ONE RUN. The Lua table is for the Sylvannas runtime (no JSON, no io, no load in that
sandbox); the JSON is for the Rust resolver, which validates Flight tasks and cannot read Lua.
Writing them from two generators is how the two halves of the platform drift apart, so both are
emitted from the same filtered edge list here and cross-checked by
tests/kernel/test_taxi_paths.lua.

TaxiPathNode.dbc (13,462 waypoints) is deliberately NOT read. That table is flight GEOMETRY; the
client flies the character itself once the hop is boarded, so half a megabyte of it would be dead
data in a catalog whose only question is connectivity.

Faction slots are determined EMPIRICALLY against Stormwind, exactly as the node tool does -- not
because this catalog stores factions, but because it ASSERTS that no kept edge crosses the faction
line. That assertion is only meaningful if the slots were read, not guessed.
"""
import json, struct, os

HERE = os.path.dirname(__file__)
DBC_DIR = os.path.join(HERE, "..", "..", "Emulators", "Mangos - Classic TBC", "extracted", "dbc")
PATH_DBC = os.path.join(DBC_DIR, "TaxiPath.dbc")
NODE_DBC = os.path.join(DBC_DIR, "TaxiNodes.dbc")
OUT_LUA = os.path.join(HERE, "..", "kernel", "catalogs", "taxi_paths.lua")
OUT_JSON = os.path.join(HERE, "..", "kernel", "catalogs", "taxi_paths.json")

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

node_recs, nread = read_dbc(NODE_DBC)
# fmt nifffssssssssssssssssxii = 24 fields: [0]=id [5]=name [22,23]=mount creature per faction
nodes = {r[0]: {"name": nread(r[5]), "m0": r[22], "m1": r[23]} for r in node_recs}

sw = next(n for n in nodes.values() if n["name"].startswith("Stormwind"))
assert (sw["m0"] == 0) != (sw["m1"] == 0), "Stormwind must be single-faction: %r" % sw
ALLIANCE_SLOT = "m0" if sw["m0"] != 0 else "m1"
HORDE_SLOT = "m1" if ALLIANCE_SLOT == "m0" else "m0"

# The SAME filter regen_taxi_nodes_catalog.py applies, restated rather than imported so the two
# tools cannot silently disagree about what a usable node is: a node offered to NEITHER faction is
# a boat/zeppelin pseudo-node, a quest-scripted cinematic flight, or dev land.
USABLE = {i for i, n in nodes.items() if n["name"] and not (n["m0"] == 0 and n["m1"] == 0)}

path_recs, _ = read_dbc(PATH_DBC)
# fmt niii = 4 fields: [0]=id [1]=from_node [2]=to_node [3]=cost (copper)
kept, excluded = [], []
for pid, src, dst, cost in path_recs:
    assert src in nodes and dst in nodes, "path %d names a node absent from TaxiNodes.dbc" % pid
    edge = {"path": pid, "from": src, "to": dst, "cost": cost}
    if src in USABLE and dst in USABLE:
        kept.append(edge)
        continue
    # DROPPED, not kept. The endpoint is a node taxi_nodes.lua already refused, so
    # TaxiNodes.resolve can never return that id -- keeping the edge would let a route lookup
    # answer "yes, connected" for a hop no flight master anywhere sells. The boat and zeppelin
    # legs among these are real travel, but they are boarded by walking onto a ship, not by
    # talking to a flight master, so they belong to a future Boat task and not to this table.
    edge["reason"] = "endpoint_not_in_node_catalog"
    edge["excluded_endpoints"] = sorted({e for e in (src, dst) if e not in USABLE})
    excluded.append(edge)

seen = set()
for e in kept:
    assert (e["from"], e["to"]) not in seen, "duplicate edge %d -> %d" % (e["from"], e["to"])
    seen.add((e["from"], e["to"]))
    a, b = nodes[e["from"]], nodes[e["to"]]
    # A flight master only sells routes his own side can fly. A surviving cross-faction edge means
    # the empirical slot probe above read the wrong column, and the in-game symptom is a Flight
    # task that boards nothing and reports no reason.
    assert (a[ALLIANCE_SLOT] and b[ALLIANCE_SLOT]) or (a[HORDE_SLOT] and b[HORDE_SLOT]), \
        "cross-faction edge %d: %s -> %s" % (e["path"], a["name"], b["name"])

kept.sort(key=lambda e: (e["from"], e["to"]))
excluded.sort(key=lambda e: e["path"])

adjacency = {}
for e in kept:
    adjacency.setdefault(e["from"], {})[e["to"]] = e

lines = []
lines.append("-- kernel/catalogs/taxi_paths.lua")
lines.append("-- GENERATED by sentinel/tools/regen_taxi_paths_catalog.py from TaxiPath.dbc (2.4.3).")
lines.append("-- Do not hand-edit; regenerate. taxi_paths.json is the same edge list for the Rust")
lines.append("-- resolver and is written by the same run -- patching one alone splits the platform.")
lines.append("--")
lines.append("-- `edges` is an ADJACENCY index, edges[from_node][to_node] = { path, cost }, so asking")
lines.append("-- \"is there a flight A -> B\" is two table lookups no matter how large the catalog is.")
lines.append("-- A flat row list would make every Flight validation a %d-row scan, and the compiler"
             % len(path_recs))
lines.append("-- validates every step of every guide.")
lines.append("--")
lines.append("-- These are DIRECT hops only. TaxiPath.dbc has no notion of a connecting flight;")
lines.append("-- chaining hops is the caller's decision and is deliberately not baked in here.")
lines.append("--")
lines.append("-- %d of the DBC's %d rows are EXCLUDED: their endpoint is a node taxi_nodes.lua"
             % (len(excluded), len(path_recs)))
lines.append("-- refused as usable by neither faction (boat/zeppelin pseudo-nodes, quest-scripted")
lines.append("-- cinematic flights, dev land). TaxiNodes.resolve can never name those ids, so an")
lines.append("-- edge reaching one could only ever answer \"connected\" about a hop no flight master")
lines.append("-- sells. The full excluded list, with reasons, is in taxi_paths.json.")
lines.append("local M = {}")
lines.append("")
lines.append("M.edges = {")
for src in sorted(adjacency):
    lines.append("    [%d] = {" % src)
    for dst in sorted(adjacency[src]):
        e = adjacency[src][dst]
        lines.append("        [%d] = { path = %d, cost = %d }," % (dst, e["path"], e["cost"]))
    lines.append("    },")
lines.append("}")
lines.append("")
lines.append("--- How many DBC rows the exclusion rule dropped. Pinned by the tests: if this moves,")
lines.append("--- the meaning of \"a flyable route\" changed and every Flight plan is affected.")
lines.append("M.excluded_edge_count = %d" % len(excluded))
lines.append("")
lines.append("""---The fare and TaxiPath id for a direct flight, or nothing.
---
---Returns nil rather than raising for an unknown source: a Flight task validating a destination
---the character cannot reach is an ordinary answer, not a defect, and the caller must be able to
---ask about any pair of node ids without pre-checking that the source flies anywhere at all.
---@param from number|nil source node id
---@param to number|nil destination node id
---@return number|nil path_id, number|string|nil cost_or_err cost in copper, or "no_route"
function M.route(from, to)
    if type(from) ~= "number" or type(to) ~= "number" then return nil, "no_route" end
    local dests = M.edges[from]
    if not dests then return nil, "no_route" end
    local edge = dests[to]
    if not edge then return nil, "no_route" end
    return edge.path, edge.cost
end

---@param from number|nil source node id
---@param to number|nil destination node id
---@return boolean always a boolean, never nil, so it reads directly in a condition
function M.has_route(from, to)
    return M.route(from, to) ~= nil
end

---Every node reachable in one hop from `from`, as a { [to_node] = { path, cost } } table.
---Empty rather than nil for an unknown source, so callers can iterate without a guard.
---@param from number|nil source node id
---@return table
function M.destinations(from)
    if type(from) ~= "number" then return {} end
    return M.edges[from] or {}
end

return M""")

open(OUT_LUA, "w").write("\n".join(lines) + "\n")

# Sorted keys and a fixed separator, because "regenerating twice produces identical bytes" is what
# makes a committed generated file reviewable as a diff instead of as noise.
json.dump({
    "source": "TaxiPath.dbc (2.4.3, Mangos Classic TBC extract)",
    "generated_by": "sentinel/tools/regen_taxi_paths_catalog.py",
    "total_dbc_rows": len(path_recs),
    "edges": [{"path": e["path"], "from": e["from"], "to": e["to"], "cost": e["cost"]} for e in kept],
    "excluded": [{"path": e["path"], "from": e["from"], "to": e["to"], "cost": e["cost"],
                  "reason": e["reason"],
                  "excluded_endpoints": [{"id": i, "name": nodes[i]["name"]}
                                         for i in e["excluded_endpoints"]]}
                 for e in excluded],
}, open(OUT_JSON, "w"), indent=2, sort_keys=True, separators=(",", ": "))
open(OUT_JSON, "a").write("\n")

print("wrote %s and %s: %d edges kept, %d excluded (of %d rows), %d source nodes"
      % (OUT_LUA, OUT_JSON, len(kept), len(excluded), len(path_recs), len(adjacency)))
