#!/usr/bin/env python3
"""Build the profile chain manifest from RestedXP guide sources.

RestedXP guides carry the authoritative route order as `#next` directives:
each guide names its successor(s), optionally class-guarded with `<< Class`
or `<< !Class` tails and `;`-separated alternatives. The importer does not
yet preserve them, so this tool re-derives the chain straight from the guide
sources and emits `chain.json` next to the compiled profiles.

Usage:
  build_chain_manifest.py <guides_dir> <projects_dir> <out_chain.json>

The manifest maps profile slugs (the importer's filename sanitization of the
guide name) to ordered next-options:

  { "entries": { "<slug>": { "name": "...", "next": [
        {"slug": "...", "class_only": "Warlock"|null, "class_not": "Warlock"|null}
  ] } } }
"""
import json
import re
import sys
from pathlib import Path


def slugify(name: str) -> str:
    """Mirror the importer's guide-name → project-filename sanitization."""
    return name.strip().replace("/", "_").replace(" ", "-")


def parse_guides(guides_dir: Path):
    """Yield (names, next_lines) per RegisterGuide block.

    One block may register several class-guarded #name lines (the same route
    published under per-class names) and several class-guarded #next lines
    (each a `;`-ordered fallback list for the classes its guard admits).
    """
    for lua in sorted(guides_dir.glob("*.lua")):
        text = lua.read_text(encoding="utf-8", errors="replace")
        names, nexts = [], []
        for line in text.splitlines():
            line = line.strip()
            if "RegisterGuide" in line:
                if names:
                    yield names, nexts
                names, nexts = [], []
            elif line.startswith("#name "):
                names.append(line[len("#name "):].strip())
            elif line.startswith("#next "):
                nexts.append(line[len("#next "):].strip())
        if names:
            yield names, nexts


def split_class_tail(text):
    """Strip a trailing `<< Class` / `<< !Class` guard; return (bare, only, not)."""
    class_only = class_not = None
    m = re.search(r"<<\s*(!?)([A-Za-z/]+)\s*$", text)
    if m:
        text = text[: m.start()].strip()
        if m.group(1) == "!":
            class_not = m.group(2)
        else:
            class_only = m.group(2)
    return text, class_only, class_not


def parse_next(next_lines):
    """Flatten class-guarded #next lines into ordered guarded options.

    A line's trailing guard applies to every `;`-alternative on that line;
    the alternatives keep their relative order as fallbacks.
    """
    options = []
    for raw in next_lines:
        line_body, line_only, line_not = split_class_tail(raw)
        for part in line_body.split(";"):
            part = part.strip()
            if not part:
                continue
            bare, class_only, class_not = split_class_tail(part)
            options.append({
                "slug": slugify(bare),
                "name": bare,
                "class_only": class_only or line_only,
                "class_not": class_not or line_not,
            })
    return options


def main():
    guides_dir, projects_dir, out_path = map(Path, sys.argv[1:4])
    entries = {}
    for names, next_lines in parse_guides(guides_dir):
        options = parse_next(next_lines)
        for name in names:
            # A #name may itself carry a class tail ("11-12 Loch Modan << !Warlock");
            # the chain is keyed by the BARE name (what #next targets reference) while
            # the importer's on-disk filename keeps the full tail — record both, plus
            # the guard, which doubles as this entry's own eligibility filter.
            bare, class_only, class_not = split_class_tail(name)
            slug = slugify(bare)
            # Later duplicate names (shared zones across guide files) keep the
            # first-seen entry — the importer disambiguated theirs with -2 suffixes
            # and the chain should reference the canonical copy.
            if slug in entries:
                continue
            entries[slug] = {
                "name": bare,
                "file_slug": slugify(name),
                "class_only": class_only,
                "class_not": class_not,
                "next": options,
            }

    # Verify referenced successors exist as imported projects; missing ones are
    # kept (the runtime skips unloadable links) but reported for the operator.
    missing = []
    for slug, e in entries.items():
        for opt in e["next"]:
            if opt["slug"] not in entries and not (projects_dir / f"{opt['slug']}.json").exists():
                missing.append(f"{slug} -> {opt['slug']}")

    out_path.write_text(json.dumps({"entries": entries}, indent=1))
    print(f"chain: {len(entries)} guides, {sum(len(e['next']) for e in entries.values())} links -> {out_path}")
    if missing:
        print(f"WARNING: {len(missing)} dangling links:")
        for m in missing[:20]:
            print(f"  {m}")


if __name__ == "__main__":
    main()
