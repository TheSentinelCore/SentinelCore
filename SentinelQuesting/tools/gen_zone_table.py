#!/usr/bin/env python3
"""Regenerate `shared/src/zone.rs::ZONE_TABLE` from the 2.4.3 client's WorldMapArea.dbc.

The zone table is generated but **checked in as source**: the DBC lives under `Emulators/` and is
deliberately not a build input, so nothing in the build graph opens it and regenerating is a
manual, auditable act. This script owns only the rows between the `ZONE_TABLE` markers; the
module documentation around them is hand-maintained.

    python3 SentinelQuesting/tools/gen_zone_table.py [--check]
    cargo test -p sentinel-models --test zone_table

`--check` verifies the checked-in table is exactly what this script would emit and exits non-zero
otherwise, without writing. Re-running without `--check` on an up-to-date tree is a no-op, because
every float is emitted as the shortest decimal that round-trips through `f32`.

Inputs
------
`Emulators/Mangos - Classic TBC/extracted/dbc/WorldMapArea.dbc`
    A `WDBC` file: 68 records x 9 fields x 36 bytes, then a 778-byte string block. Read through the
    Mangos `WorldMapAreaEntry` layout (`src/game/Server/DBCStructure.h`) and its `"xinxffffi"`
    format string (`DBCfmt.h`):
        [0] id  [1] map_id  [2] area_id  [3] internal_name (string-block offset)
        [4] locLeft  [5] locRight  [6] locTop  [7] locBottom  [8] virtual_map_id
    The bounds are stored as raw int32 bit patterns and are *reinterpreted* as f32, never cast.

`sentinel/docs/adr/restedxp guides/`
    The vendored guide corpus, used only to prove the alias table is complete: every zone spelling
    the corpus writes in field 0 of a `.goto`/`.waypoint` must resolve, or this script refuses to
    emit. It never invents an alias from the corpus -- unresolved tokens are a hard failure that a
    human has to adjudicate, because a wrong alias is not an error at runtime, it is a character
    walking to the wrong continent.

What this script asserts before it will write anything
------------------------------------------------------
* the DBC header matches the expected record/field/size shape;
* the UiMapID block rule reproduces all nine ids that were known independently of it;
* no two alias spellings collide after normalisation;
* every corpus zone token resolves.
"""

import argparse
import os
import re
import struct
import sys
from collections import Counter, defaultdict

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.normpath(os.path.join(HERE, "..", ".."))
DBC = os.path.join(REPO, "Emulators", "Mangos - Classic TBC", "extracted", "dbc", "WorldMapArea.dbc")
CORPUS = os.path.join(REPO, "sentinel", "docs", "adr", "restedxp guides")
ZONE_RS = os.path.join(REPO, "SentinelQuesting", "shared", "src", "zone.rs")

BEGIN = "pub const ZONE_TABLE: &[(u32, &[&str], ZoneMap)] = &[\n"
END = "];\n"

# UiMapIDs postdate 2.4.3 and appear in no DBC. They form two contiguous runs in DBC-id order: the
# 51 records that shipped in 1.x (through the three vanilla battlegrounds) based at 1411, and the
# 17 added in TBC based at 1941. The split is the first TBC record, EversongWoods (DBC id 462,
# immediately after ArathiBasin at 461). That is a claim about the data, so it is asserted against
# the nine known ids below rather than trusted.
VANILLA_BASE, TBC_BASE = 1411, 1941
FIRST_TBC_RECORD = "EversongWoods"

# Recovered independently of the block rule: seven from the previously hand-transcribed table and
# from corpus lines that spell the same location both numerically and by name.
KNOWN_UI_MAP_IDS = {
    "Elwynn": 1429, "DunMorogh": 1426, "LochModan": 1432, "Redridge": 1433,
    "Westfall": 1436, "Wetlands": 1437, "Darkshore": 1439, "Stormwind": 1453,
    "Ironforge": 1455,
}

# Spellings normalisation cannot bridge. Every one is a token the corpus actually writes; none is
# fuzzy-matched or inferred. `Outland -> Expansion01` is deliberately absent: it is true, but the
# corpus never navigates that row, and an unused alias is the one invented entry in a table whose
# whole claim is that nothing is invented.
ALIAS = {
    # Blizzard's own misspellings, preserved verbatim in the DBC string block.
    "Hillsbrad Foothills": "Hilsbrad",       # one L in the DBC
    "Azshara": "Aszhara",                    # transposed
    "Orgrimmar": "Ogrimmar",                 # no R
    "Darnassus": "Darnassis",                # final S
    # Display names carrying an article or a region word the internal name drops.
    "The Barrens": "Barrens",
    "The Hinterlands": "Hinterlands",
    "Stranglethorn Vale": "Stranglethorn",
    "Elwynn Forest": "Elwynn",
    "Redridge Mountains": "Redridge",
    "Dustwallow Marsh": "Dustwallow",
    "Hellfire Peninsula": "Hellfire",
    "Arathi Highlands": "Arathi",
    "Alterac Mountains": "Alterac",
    "Tirisfal Glades": "Tirisfal",
    "Silverpine Forest": "Silverpine",
    "Eastern Kingdoms": "Azeroth",
    # RestedXP's two spellings for the Stormwind city map.
    "Stormwind City": "Stormwind",
    "StormwindClassic": "Stormwind",
}


def f32(x):
    return struct.unpack("<f", struct.pack("<f", x))[0]


def fbits(x):
    return struct.pack("<f", x)


def r32(x):
    """Shortest decimal that round-trips through f32 -- what Rust's `{:?}` prints.

    Emitting anything shorter is how the previous hand-written table lost `DunMorogh.top` by 1 ULP
    and `Stormwind.right` by 8: both were the DBC value printed at 7 and 6 significant digits.
    """
    x = f32(x)
    for p in range(1, 18):
        s = "%.*g" % (p, x)
        if fbits(float(s)) != fbits(x):
            continue
        if "e" in s or "E" in s:          # never emit exponent form into the table
            s = format(float(s), "f").rstrip("0")
            if s.endswith("."):
                s += "0"
            assert fbits(float(s)) == fbits(x), (x, s)
        return s if "." in s else s + ".0"
    raise AssertionError("no round-tripping decimal for %r" % x)


def read_dbc():
    with open(DBC, "rb") as fh:
        blob = fh.read()
    magic, n_rec, n_field, rec_size, sb_size = struct.unpack_from("<4sIIII", blob, 0)
    assert magic == b"WDBC", "not a WDBC file: %r" % magic
    assert rec_size == n_field * 4 == 36 and n_rec == 68, (n_rec, n_field, rec_size)
    sb_off = 20 + n_rec * rec_size
    sblock = blob[sb_off:sb_off + sb_size]

    def get_str(off):
        return sblock[off:sblock.find(b"\0", off)].decode("utf-8")

    rows = []
    for r in range(n_rec):
        raw = struct.unpack_from("<%dI" % n_field, blob, 20 + r * rec_size)
        as_i = lambda k: struct.unpack("<i", struct.pack("<I", raw[k]))[0]
        as_f = lambda k: struct.unpack("<f", struct.pack("<I", raw[k]))[0]
        rows.append(dict(id=as_i(0), map_id=as_i(1), area_id=as_i(2), name=get_str(raw[3]),
                         left=as_f(4), right=as_f(5), top=as_f(6), bottom=as_f(7), vmap=as_i(8)))
    rows.sort(key=lambda z: z["id"])
    return rows


def assign_ui_map_ids(rows):
    names = [r["name"] for r in rows]
    split = names.index(FIRST_TBC_RECORD)
    assert split == 51, "vanilla block is not 51 records (got %d)" % split
    assert rows[split - 1]["name"] == "ArathiBasin" and len(rows) - split == 17
    for k, r in enumerate(rows[:split]):
        r["uid"] = VANILLA_BASE + k
    for k, r in enumerate(rows[split:]):
        r["uid"] = TBC_BASE + k
    by_name = {r["name"]: r for r in rows}
    wrong = [(n, by_name[n]["uid"], want) for n, want in KNOWN_UI_MAP_IDS.items()
             if by_name[n]["uid"] != want]
    assert not wrong, "block rule disagrees with a known UiMapID (name, derived, known): %r" % wrong
    return len(KNOWN_UI_MAP_IDS)


def norm(s):
    return re.sub(r"[^A-Za-z0-9]", "", s).lower()


def corpus_zone_tokens():
    """Every field-0 *name* token of a `.goto`/`.waypoint`, with its use count.

    Trailing `-- dev comments` and `<< raceGates` are stripped first; the numeric and raw-world
    (`1439/1`) forms are not name tokens and are skipped.
    """
    tok = Counter()
    for root, _, files in os.walk(CORPUS):
        for fn in files:
            if not fn.endswith(".lua"):
                continue
            with open(os.path.join(root, fn), encoding="utf-8", errors="replace") as fh:
                for line in fh:
                    m = re.search(r"\.(?:goto|waypoint)\s+([^\n]+)", line)
                    if not m:
                        continue
                    f0 = m.group(1).split("--")[0].split("<<")[0].strip().split(",")[0].strip()
                    if f0 and "/" not in f0 and not re.fullmatch(r"\d+", f0):
                        tok[f0] += 1
    return tok


def build(rows):
    by_norm = {norm(r["name"]): r["name"] for r in rows}
    assert len(by_norm) == len(rows), "two DBC internal names normalise alike"

    tok = corpus_zone_tokens()
    unresolved = {t: c for t, c in tok.items()
                  if norm(t) not in by_norm and t not in ALIAS}
    assert not unresolved, (
        "corpus zone tokens no alias covers -- add them to ALIAS deliberately, never by nearest "
        "match: %r" % sorted(unresolved.items(), key=lambda kv: -kv[1]))

    extra = defaultdict(list)
    for spelling, target in ALIAS.items():
        assert target in by_norm.values(), "alias %r targets a non-existent row %r" % (spelling, target)
        extra[target].append(spelling)

    claimed = {}
    for r in rows:
        r["aliases"] = [r["name"]] + sorted(extra.get(r["name"], []))
        for a in r["aliases"]:
            k = norm(a)
            assert k not in claimed, "alias %r is claimed by both %s and %s" % (a, claimed[k], r["name"])
            claimed[k] = r["name"]
    return len(tok), sum(tok.values()), len(claimed)


def render(rows):
    out = []
    for r in rows:
        aliases = ", ".join('"%s"' % a for a in r["aliases"])
        note = ("" if r["vmap"] == -1 else
                " -- virtual_map_id %d is DISPLAY ONLY; continent stays %d"
                % (r["vmap"], r["map_id"]))
        out.append(
            "    // %s  (WorldMapArea id %d, area %d)%s\n"
            "    (%d, &[%s],\n"
            "     ZoneMap { continent: %d, top: %s, left: %s, bottom: %s, right: %s }),"
            % (r["name"], r["id"], r["area_id"], note, r["uid"], aliases, r["map_id"],
               r32(r["top"]), r32(r["left"]), r32(r["bottom"]), r32(r["right"])))
    return "\n".join(out) + "\n"


def splice(current, rows_text):
    i = current.index(BEGIN) + len(BEGIN)
    j = current.index("\n" + END, i) + 1
    return current[:i] + rows_text + current[j:]


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--check", action="store_true",
                    help="verify the checked-in table matches; write nothing")
    args = ap.parse_args()

    rows = read_dbc()
    known = assign_ui_map_ids(rows)
    distinct, uses, alias_keys = build(rows)
    print("WorldMapArea.dbc: %d records" % len(rows))
    print("UiMapID block rule agrees with all %d independently-known ids" % known)
    print("corpus: %d distinct zone tokens, %d .goto/.waypoint uses, 0 unresolved" % (distinct, uses))
    print("alias keys: %d, all distinct after normalisation" % alias_keys)

    with open(ZONE_RS, encoding="utf-8") as fh:
        current = fh.read()
    updated = splice(current, render(rows))

    if args.check:
        if updated != current:
            print("STALE: shared/src/zone.rs does not match the DBC; re-run without --check",
                  file=sys.stderr)
            return 1
        print("shared/src/zone.rs is up to date with the DBC")
        return 0
    if updated == current:
        print("shared/src/zone.rs already up to date (no write)")
        return 0
    with open(ZONE_RS, "w", encoding="utf-8") as fh:
        fh.write(updated)
    print("wrote %s" % ZONE_RS)
    return 0


if __name__ == "__main__":
    sys.exit(main())
