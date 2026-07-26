#!/usr/bin/env python3
"""Fail loudly on line-number citations into LIVING files.

A citation written as a line number rots silently: any edit above it retargets the
number onto a different line that still exists, so nothing fails and no one notices.
This has been repaired and re-broken four separate times in this tree.

The rule:

  * Line numbers are acceptable ONLY for the vendored RestedXP corpus under
    `sentinel/docs/adr/restedxp guides` — immutable input data, never edited.
  * Everything else must be an ANCHOR that survives edits or fails loudly:
      - ADR sections  -> §7.3.3 "Step types exercised"     (section + quoted heading)
      - Rust items    -> compiler/src/lib.rs::parse_class_guard   (path + symbol)
      - Prose spans   -> enough quoted text to be unique and greppable

Run:  python3 tools/check_citation_anchors.py
Exit: 0 when clean, 1 when any rot-prone citation survives.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

# A line-number citation is *a locator followed by a number*. Enumerating the spellings
# actually present in the tree is what let a whole family of ~25 survive every prior audit:
# they matched `§7.2:1448` (colon) but not `§7.2 line 1448` (space). Enumerating nine
# spellings instead of two is the same mistake with a bigger list — an adversarial review
# injected eleven plausible variants and this checker caught two.
#
# So the patterns below describe the SHAPE, not the samples. Two building blocks:
#   SEP   — anything that can sit between a locator and its number: `:`, `#L`, `@`,
#           `line`/`lines`/`ln`/`L`, `near`/`around`, or plain whitespace after a comma.
#   RANGE — an optional `-NNN` tail, with any dash character.
# Adding a tenth spelling should require no code change. If it does, that is a bug in the
# rule, not a missing sample.
SEP = r"(?:\s*[:@#]\s*L?|\s*,?\s*(?:lines?|ln|L|near|around)\s*|\s*#L\s*)"
RANGE = r"(?:\s*[-–—]\s*[0-9]+)?"

PATTERNS: list[tuple[str, str]] = [
    # `§7.2:1448`, `§7.2: 1448`, `§7.2 line 1448`, `§7.2 @1448`, `§7.2 ln 1448`, `§7.2 L1448`
    #
    # 3+ digits. ADR 07 is ~2,300 lines, so every real line citation is 3-4 digits, while a
    # 1-2 digit number after a section is almost always a quantity — `§7.2: 32-byte digest`
    # is a size, not a line, and flagging it would train the reader to ignore the check.
    ("section-locator",    rf"§[0-9][0-9.]*{SEP}[0-9]{{3,}}{RANGE}"),
    # `(lines 1670-1975)`, `(line 1448)`
    ("paren-lines",        r"\(\s*lines?\s+[0-9]+(?:\s*[-–—]\s*[0-9]+)?\s*\)"),
    # `at line 1448`, `near 1448`, `around line 1448`
    ("at-line",            r"\b(?:at|near|around)\s+lines?\s+[0-9]+"),
    # A bare `line 1448` with no locator. 3+ digits only; the 1-2 digit case is handled by
    # FIXTURE_LOCAL below, which is scoped rather than blanket.
    ("bare-line-number",   r"\blines?\s+[0-9]{3,}"),
    # `file.rs:12`, `file.rs:12-34`, `file.rs L301`, `file.md#L1448`, for every source
    # extension in the workspace.
    ("source-file-line",   rf"\b[\w./-]+\.(?:rs|toml|json|md|py|lua){SEP}[0-9]+{RANGE}"),
    # `ADR 07 L1448`, `ADR 1400 declares` — a document named without a section, then a number.
    ("doc-locator",        r"\bADR\s+[0-9]{2}\s*(?:[:@#]\s*L?|\s+L|\s+lines?\s+)[0-9]{3,}"),
]

# The one legal family: vendored corpus `.lua:N`. Those files are input data — never
# edited — and all corpus citations are machine-verified correct. LEAVE THEM ALONE.
#
# Deliberately NOT flagged, and not an oversight: the bare `:16256` / `TBC:11260` /
# `DG:2551` / `A-11-23:732` shorthand. Those are continuation citations into the same
# corpus guide named earlier in the paragraph — still immutable input data. They carry no
# file extension, so no pattern below can reach them, and none should: a repo-wide ban on
# `:NNNN` would flag JSON, URLs and timestamps without finding a single rot-prone citation.
CORPUS_LINE = re.compile(r"\b[\w'. -]+\.lua\s*:\s*[0-9]+")

# `line 7 here`, `line 8 here` etc. index into a test's OWN inline fixture string, not into
# any file on disk. They move only when the fixture beside them moves.
#
# SCOPED, not blanket. A bare `\blines?\s+[0-9]{1,2}\b` exemption would whitelist every
# short line reference in the repo — including `lib.rs, line 32`, which is exactly where
# `parse_class_guard` really lives, so the one citation most likely to be written by hand
# would sail through. The exemption therefore applies only when the surrounding line names
# no external target: no file extension, no `§`, no `ADR`. If any of those appear, the
# citation points somewhere that can move, and it is flagged.
FIXTURE_LOCAL = re.compile(r"\blines?\s+[0-9]{1,2}\b")
NAMES_EXTERNAL_TARGET = re.compile(
    r"§|\bADR\b|\.(?:rs|toml|json|md|py|lua)\b", re.IGNORECASE
)


def is_fixture_local(hit: str, whole_line: str) -> bool:
    """A 1-2 digit `line N` counts as fixture-local only if nothing on the line names a
    file, an ADR or a section that the number could be indexing into."""
    return bool(FIXTURE_LOCAL.fullmatch(hit)) and not NAMES_EXTERNAL_TARGET.search(
        whole_line
    )

# Verbatim quotations of text that lives elsewhere. Editing these would falsify the quote,
# so they are allowed — but keyed on the EXACT quoted substring, so the exemption cannot
# silently widen to cover a new citation. Each entry states what is quoted and why the
# line number inside it is legal.
VERBATIM_QUOTES: dict[str, str] = {
    # ADR 07 §7.3.3's task-4 `_comment`, quoted whole. Its "lines 265-268" are corpus lines
    # of `A-11-23.lua` (cited explicitly as `A-11-23.lua:265-268` further down this file),
    # i.e. immutable input data. Search the ADR for `THE MULTI-DEPENDENCY TASK`.
    "Source lines 265-268 are the author's XXREQ hack":
        "verbatim ADR 07 §7.3.3 task-4 _comment; its line numbers are corpus (A-11-23.lua)",
}


# Directories that hold build output or VCS metadata, never citations.
SKIP_DIRS = {"target", ".git"}

# Text formats a citation can be written in. Binaries and lockfiles are skipped.
SCAN_SUFFIXES = {".rs", ".md", ".json", ".toml", ".py", ".lua", ".txt", ".sh", ".yml", ".yaml"}


def scanned_files() -> list[Path]:
    """Every text file under the workspace — a filesystem walk, not `git ls-files`.

    Deliberately not git-driven: `tools/` is gitignored in this repo (though
    `tools/build_chain_manifest.py` is force-added), so a `git ls-files` scan would
    silently skip a whole directory. A citation audit that can be defeated by .gitignore
    is exactly the kind of silent gap this script exists to close.
    """
    keep = []
    for path in ROOT.rglob("*"):
        if not path.is_file():
            continue
        if SKIP_DIRS.intersection(path.relative_to(ROOT).parts):
            continue
        if path.suffix not in SCAN_SUFFIXES:
            continue
        if path.name == "Cargo.lock":
            continue
        if path.resolve() == Path(__file__).resolve():
            continue
        keep.append(path)
    return sorted(keep)


def scan() -> list[tuple[str, int, str, str, str]]:
    findings = []
    for path in scanned_files():
        try:
            text = path.read_text(encoding="utf-8")
        except (UnicodeDecodeError, OSError):
            continue
        for lineno, line in enumerate(text.splitlines(), start=1):
            # Blank out the legal corpus citations so a corpus `.lua:215-231` on the same
            # line as real prose cannot mask, or be mistaken for, a rot-prone citation.
            masked = CORPUS_LINE.sub(lambda m: "#" * len(m.group(0)), line)
            for quoted in VERBATIM_QUOTES:
                masked = masked.replace(quoted, "#" * len(quoted))
            for label, pattern in PATTERNS:
                for match in re.finditer(pattern, masked):
                    hit = match.group(0)
                    if label == "bare-line-number" and is_fixture_local(hit, line):
                        continue
                    findings.append(
                        (str(path.relative_to(ROOT)), lineno, label, hit, line.strip())
                    )
    return findings


def main() -> int:
    findings = scan()
    scanned = len(scanned_files())
    print(f"scanned {scanned} files under {ROOT} (target/ excluded)")
    print("patterns: " + ", ".join(f"{label}" for label, _ in PATTERNS))
    print("allowed:  vendored corpus `<guide>.lua:N` citations only")
    print()
    if not findings:
        print("RESULT: 0 line-number citations into living files. Clean.")
        return 0
    print(f"RESULT: {len(findings)} rot-prone citation(s) still present:")
    for rel, lineno, label, hit, line in findings:
        print(f"  {rel}:{lineno}  [{label}]  {hit!r}")
        print(f"      {line}")
    return 1


if __name__ == "__main__":
    sys.exit(main())
