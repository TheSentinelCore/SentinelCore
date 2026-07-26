#!/usr/bin/env python3
"""Regenerate tests/fixtures/spell_chain_tbc243.lua from tbcmangos.sqlite.

WHY A GENERATOR AND NOT A TEST THAT OPENS THE DATABASE
-----------------------------------------------------
tbcmangos.sqlite is 298 MB and is gitignored (`.gitignore`, the `tbcmangos.sqlite` entry).
No CI runner has it, and the Sylvannas sandbox that must be able to load the offline suite has
neither sqlite nor `io`. A test that queried the database would therefore SKIP everywhere except
one developer's laptop -- and a skipping test reads as a passing test, which is the exact failure
mode `tests/kernel/test_spell_catalog_gcd_truth.lua` documents under "what this suite cannot see".

So the database is consulted HERE, offline and on purpose, and the answer is committed as a Lua
table that `tests/kernel/test_catalog_rank_chains.lua` compares the catalogs against on every
`luajit sentinel/tests/run_offline.lua`. The fixture carries the evidence (SpellName, rank label,
BaseLevel) alongside each id, so a failure prints WHY the array is wrong, not merely that it is.

USAGE
-----
    python3 sentinel/tools/regen_catalog_chain_fixture.py            # rewrite the fixture
    python3 sentinel/tools/regen_catalog_chain_fixture.py --check    # exit 1 if it would change

Run --check whenever the database is swapped or a rank array is hand-edited. It is the only thing
that can catch the fixture drifting away from the database; the offline test cannot.

WHAT THE DATABASE CAN AND CANNOT PROVE
-------------------------------------
`spell_chain` is the explicit rank-progression table: (spell_id, prev_spell, first_spell, rank).
Where it has rows for a spell family, membership AND order are both proved, and the emitted chain
goes under `chains`. Some families have NO rows at all -- talent ranks (Vengeance, Frostbite),
paladin auras (Retribution Aura), single-rank pet spells (Freeze). For those the database can still
prove that every declared id exists, shares one SpellName, and ascends by rank label / BaseLevel,
but it cannot prove that nothing is MISSING unless the SpellName+Attributes family happens to match
the declared set exactly. Those go under `unchained`, each carrying an explicit
`completeness` verdict so the gap is recorded rather than hidden.
"""

import argparse
import os
import re
import sqlite3
import sys

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
DB = os.path.join(REPO, "tbcmangos.sqlite")
SPELL_LUA = os.path.join(REPO, "sentinel", "kernel", "catalogs", "spell.lua")
AURA_LUA = os.path.join(REPO, "sentinel", "kernel", "catalogs", "aura.lua")
FIXTURE = os.path.join(REPO, "sentinel", "tests", "fixtures", "spell_chain_tbc243.lua")

# aura.lua arrays with no spell.lua counterpart, and the id the chain is anchored on.
AURA_ONLY_ANCHORS = {
    "frostbite_debuffs": 11071,
    "water_elemental_freeze": 33395,
}

# aura.lua array -> spell.lua key it must be the SAME chain as. The seal_of_righteousness pair is
# why this mapping exists: both files carried the same wrong array, so checking either alone
# against the other would have agreed.
AURA_ALIASES = {
    "seal_of_command_ranks": "seal_of_command",
    "seal_of_righteousness_ranks": "seal_of_righteousness",
    "blessing_of_might_ranks": "blessing_of_might",
    "retribution_aura_ranks": "retribution_aura",
    "vengeance_proc_auras": "vengeance_proc",
    "frost_nova_debuffs": "frost_nova",
    "ice_barrier_auras": "ice_barrier",
    "mana_shield_auras": "mana_shield",
    "polymorph_debuffs": "polymorph",
}

# Arrays that are deliberately NOT rank chains. Every entry needs a reason, because the test
# fails on any array it cannot classify -- that is how a newly added array gets noticed.
CURATED = {
    "hard_immunity_auras": "hand-picked cross-class immunities: Divine Shield ranks 1-2 (642/1020) "
                           "plus Ice Block (45438). Three spells, two families, one question.",
}

# Arrays that must equal the concatenation of other arrays, in order.
DERIVED = {
    "all_frozen_debuffs": ["frost_nova_debuffs", "frostbite_debuffs", "water_elemental_freeze"],
}


def load_chain(cur):
    rows = cur.execute("SELECT spell_id, prev_spell, first_spell, rank FROM spell_chain").fetchall()
    by_id = {r[0]: r for r in rows}
    by_first = {}
    for r in rows:
        by_first.setdefault(r[2], []).append(r)
    return by_id, by_first


def chain_for(by_id, by_first, anchor):
    """Transitive reconstruction of the rank chain containing `anchor`, or None.

    A first_spell sometimes has no row of its own (Seal of Righteousness rank 1, id 20154) and a
    mid-chain rank can be reachable only as some other row's prev_spell (rank 2, id 21084). Taking
    `SELECT ... WHERE first_spell = ?` alone drops both, so pull them back in from prev_spell.
    """
    row = by_id.get(anchor)
    first = row[2] if row else (anchor if anchor in by_first else None)
    if first is None:
        return None
    members = {s: rk for (s, _p, _f, rk) in by_first.get(first, [])}
    members.setdefault(first, 1)
    changed = True
    while changed:
        changed = False
        for (_s, prev, _f, rk) in list(by_first.get(first, [])):
            if prev and prev not in members:
                members[prev] = rk - 1
                changed = True
    return [sid for sid, _rk in sorted(members.items(), key=lambda kv: kv[1])]


def tmpl(cur, sid):
    return cur.execute(
        "SELECT Id, SpellName, Rank1, BaseLevel, Attributes FROM spell_template WHERE Id=?",
        (sid,),
    ).fetchone()


def parse_spell_lua():
    """(key, ids, description) for every spell.lua entry carrying a `ranks` array."""
    src = open(SPELL_LUA, encoding="utf-8").read()
    out = []
    # The closing `},` is NOT end-of-line for every entry -- ice_barrier, judgement,
    # avenging_wrath and counterspell carry a trailing `-- cat .../time ...` note. Anchoring on
    # `},$` silently dropped ice_barrier from the fixture, and the test caught it as
    # "no fixture entry" rather than passing over an unaudited array.
    for m in re.finditer(r"^ {4}(\w+) = \{(.*?)\},(?:\s*--.*)?$", src, re.M):
        key, body = m.group(1), m.group(2)
        rm = re.search(r"ranks = \{([^}]*)\}", body)
        if not rm:
            continue
        dm = re.search(r'description = "([^"]*)"', body)
        out.append((key, [int(x) for x in re.findall(r"\d+", rm.group(1))],
                    dm.group(1) if dm else None))
    return out


def parse_aura_lua():
    """(field, ids) for every array literal in aura.lua's table constructor."""
    src = open(AURA_LUA, encoding="utf-8").read()
    head = src.split("local ok_buff_manager")[0]
    return [(m.group(1), [int(x) for x in re.findall(r"\d+", m.group(2))])
            for m in re.finditer(r"^ {4}(\w+) = \{([^}]*)\},", head, re.M)]


def evidence(cur, ids):
    names, ranks, levels = [], [], []
    for sid in ids:
        row = tmpl(cur, sid)
        if row is None:
            raise SystemExit("id %d has no spell_template row -- refusing to emit a fixture" % sid)
        names.append(row[1])
        ranks.append(row[2] or "")
        levels.append(row[3])
    return names, ranks, levels


def completeness(cur, ids):
    """Can SpellName+Attributes prove nothing is missing? Returns (verdict, superset)."""
    anchor = tmpl(cur, ids[0])
    fam = cur.execute(
        "SELECT Id FROM spell_template WHERE SpellName=? AND Attributes=? ORDER BY BaseLevel, Id",
        (anchor[1], anchor[4]),
    ).fetchall()
    fam_ids = [r[0] for r in fam]
    if sorted(fam_ids) == sorted(ids):
        return "proved-by-SpellName+Attributes", fam_ids
    return "UNPROVED -- SpellName+Attributes does not isolate this family", fam_ids


def lua_list(values, quote=False):
    if quote:
        return "{ " + ", ".join('"%s"' % str(v).replace('"', '\\"') for v in values) + " }"
    return "{ " + ", ".join(str(v) for v in values) + " }"


def render(cur):
    by_id, by_first = load_chain(cur)
    L = []
    w = L.append
    w("-- tests/fixtures/spell_chain_tbc243.lua")
    w("-- GENERATED by sentinel/tools/regen_catalog_chain_fixture.py -- DO NOT HAND-EDIT.")
    w("--")
    w("-- The rank progression of every array in kernel/catalogs/spell.lua and")
    w("-- kernel/catalogs/aura.lua, taken from `spell_chain` joined to `spell_template` in")
    w("-- tbcmangos.sqlite (MaNGOS TBC 2.4.3, %d bytes). The database is gitignored, so this table"
      % os.path.getsize(DB))
    w("-- is the only form of that answer the offline suite -- or CI -- can see.")
    w("--")
    w("-- `chains`    -- `spell_chain` has rows: membership AND order are both proved.")
    w("-- `unchained` -- no `spell_chain` rows. Ids proved to exist, share one SpellName and ascend;")
    w("--                `completeness` says whether the database can also prove none is missing.")
    w("-- Regenerate with:  python3 sentinel/tools/regen_catalog_chain_fixture.py")
    w("-- Verify in place:  python3 sentinel/tools/regen_catalog_chain_fixture.py --check")
    w("")
    w("return {")
    w('    source = "tbcmangos.sqlite (MaNGOS TBC 2.4.3) spell_chain JOIN spell_template",')

    chains, unchained = {}, {}
    for key, ids, desc in parse_spell_lua():
        db_ids = chain_for(by_id, by_first, ids[0])
        (chains if db_ids else unchained)[key] = (db_ids or ids, desc)
    for field, ids in parse_aura_lua():
        if field not in AURA_ONLY_ANCHORS:
            continue
        db_ids = chain_for(by_id, by_first, AURA_ONLY_ANCHORS[field])
        (chains if db_ids else unchained)[field] = (db_ids or ids, None)

    w("")
    w("    -- ------------------------------------------------------------------")
    w("    -- Proved by spell_chain: these arrays must match EXACTLY, in order.")
    w("    -- ------------------------------------------------------------------")
    w("    chains = {")
    for key in sorted(chains):
        ids, _desc = chains[key]
        names, ranks, levels = evidence(cur, ids)
        distinct = sorted(set(names))
        w("        %s = {" % key)
        w("            ids = %s," % lua_list(ids))
        w("            levels = %s," % lua_list(levels))
        w("            names = %s," % lua_list(distinct, quote=True))
        w("            rank_labels = %s," % lua_list(ranks, quote=True))
        w("        },")
    w("    },")

    w("")
    w("    -- ------------------------------------------------------------------")
    w("    -- No spell_chain rows. Read `completeness` before trusting these.")
    w("    -- ------------------------------------------------------------------")
    w("    unchained = {")
    for key in sorted(unchained):
        ids, _desc = unchained[key]
        names, ranks, levels = evidence(cur, ids)
        verdict, superset = completeness(cur, ids)
        w("        %s = {" % key)
        w("            ids = %s," % lua_list(ids))
        w("            levels = %s," % lua_list(levels))
        w("            names = %s," % lua_list(sorted(set(names)), quote=True))
        w("            rank_labels = %s," % lua_list(ranks, quote=True))
        w('            completeness = "%s",' % verdict)
        w("            same_name_same_attributes = %s," % lua_list(superset))
        w("        },")
    w("    },")

    w("")
    w("    -- aura.lua array -> the spell.lua key it must be the same chain as.")
    w("    aura_aliases = {")
    for field in sorted(AURA_ALIASES):
        w('        %s = "%s",' % (field, AURA_ALIASES[field]))
    w("    },")
    w("")
    w("    -- Deliberately not rank chains. The test fails on any array missing from every")
    w("    -- section, so a new array cannot slip in unclassified.")
    w("    curated = {")
    for field in sorted(CURATED):
        w('        %s = "%s",' % (field, CURATED[field]))
    w("    },")
    w("")
    w("    -- Must equal the concatenation of the named arrays, in this order.")
    w("    derived = {")
    for field in sorted(DERIVED):
        w("        %s = %s," % (field, lua_list(DERIVED[field], quote=True)))
    w("    },")
    w("}")
    return "\n".join(L) + "\n"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--check", action="store_true",
                    help="exit 1 if regeneration would change the fixture")
    args = ap.parse_args()
    if not os.path.exists(DB):
        sys.exit("tbcmangos.sqlite not found at %s -- this tool needs the database; the offline "
                 "test does not." % DB)
    con = sqlite3.connect("file:%s?mode=ro" % DB, uri=True)
    text = render(con.cursor())
    if args.check:
        current = open(FIXTURE, encoding="utf-8").read() if os.path.exists(FIXTURE) else ""
        if current != text:
            sys.exit("FIXTURE IS STALE: %s does not match tbcmangos.sqlite. Re-run without "
                     "--check." % FIXTURE)
        print("Fixture matches tbcmangos.sqlite.")
        return
    os.makedirs(os.path.dirname(FIXTURE), exist_ok=True)
    with open(FIXTURE, "w", encoding="utf-8") as fh:
        fh.write(text)
    print("Wrote %s" % FIXTURE)


if __name__ == "__main__":
    main()
