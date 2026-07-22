# Import Fidelity Specification

## Purpose

The RestedXP importer converts raw guide text into authoring `Project` data. Today it silently
discards `.goto` coordinates, downgrades gating/completion commands to inert `Comment` actions,
and ignores class suffixes, sticky/loop directives, and typo'd directives. This capability makes
import faithful: every command and directive is parsed and typed, coordinates survive, and nothing
non-trivial is silently dropped. Coverage bar: `The Burning Crusade.lua` (~250 sub-guides, ~70
commands, ~45 directives, including source typos).

## Requirements

### Requirement: Goto Coordinate Preservation

The importer MUST parse coordinate arguments present on `.goto` commands and populate the
authoring `TravelAction.position` field, instead of relying only on the destination name string.

#### Scenario: Goto with explicit coordinates

- GIVEN a step containing `.goto <map/zone> <x> <y> [<z>]`
- WHEN the importer builds the step's actions
- THEN the resulting `TravelAction` MUST carry a non-null `position` with the parsed map/x/y/z

#### Scenario: Goto with zone name only

- GIVEN a `.goto` command with no numeric coordinate arguments
- WHEN the importer builds the action
- THEN `destination` MUST be set to the zone name and `position` MAY remain null, without raising
  an error

### Requirement: Typed Condition Lowering for Gating/Completion Commands

The importer MUST lower `.complete`, `.collect`, `.itemcount`, `.isOnQuest`, `.isQuestComplete`,
`.isQuestTurnedIn`, and `.isQuestAvailable` into typed authoring `Condition` expressions (attached
to the action or step), not `Comment` actions, whenever arguments parse successfully.

#### Scenario: Well-formed gating command

- GIVEN a step with `.isQuestComplete 1234`
- WHEN the importer processes the command
- THEN it MUST produce a typed condition referencing quest `1234`, not a `Comment`

#### Scenario: Malformed arguments

- GIVEN a gating command with unparseable arguments
- WHEN the importer processes it
- THEN it MUST preserve the command as a typed, inert action carrying a diagnostic (never a bare
  `Comment` with no diagnostic)

### Requirement: Per-Line Class Suffix Parsing

The importer MUST recognize a trailing `<< ClassName` suffix on any guide line and attach it as a
class-restriction annotation on the owning action.

#### Scenario: Class-restricted line

- GIVEN a line ending in `<< Warrior`
- WHEN the importer parses the line
- THEN the produced action MUST carry `class_restriction = "Warrior"`

### Requirement: Sticky and Loop Directive Handling

The importer MUST parse `#sticky` and `#loop` directives and preserve them as structured metadata
on the owning step or operation, rather than ignoring them.

#### Scenario: Sticky step

- GIVEN a step preceded by `#sticky`
- WHEN the importer builds the operation
- THEN the operation MUST carry a `sticky = true` flag

### Requirement: Typo-Tolerant Directive Parsing

The importer MUST recognize known directive typo variants (`#compltewith`, `#requries`, `#lable`,
and other single-edit-distance variants of supported directives) as their canonical directive, and
MUST emit an informational diagnostic noting the tolerated typo.

#### Scenario: Known typo

- GIVEN a directive spelled `#compltewith`
- WHEN the importer parses it
- THEN it MUST be treated as `#completewith` AND a diagnostic MUST record the substitution

### Requirement: Multi-Guide Bundle Splitting

The importer MUST split a single source file containing multiple guide headers into one output
`Project` per sub-guide, preserving each sub-guide's own header metadata and step boundaries.

#### Scenario: Bundle file

- GIVEN a source file with N guide header blocks (e.g. `The Burning Crusade.lua`, ~250 sub-guides)
- WHEN the importer runs
- THEN it MUST emit N distinct `Project` outputs, each scoped to its own guide's steps

### Requirement: Never-Drop Policy for Non-Core Commands

Any parsed command or directive not covered by leveling-core semantic lowering MUST still be
parsed into a typed, inert-preserved action or annotation carrying a per-command diagnostic. It
MUST NOT be silently discarded, and MUST NOT collapse into a bare `Comment` with no diagnostic.

#### Scenario: Unrecognized but parseable command

- GIVEN a command not in the leveling-core set (e.g. `.equip`, `.skill`)
- WHEN the importer processes it
- THEN it MUST produce a typed inert action with a diagnostic naming the command and its raw
  arguments

#### Scenario: Corpus-wide never-drop check

- GIVEN the full `The Burning Crusade.lua` bundle
- WHEN it is imported
- THEN zero actions MUST be bare `Comment` with no diagnostic trail for any recognized command or
  directive
