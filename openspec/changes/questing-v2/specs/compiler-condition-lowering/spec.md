# Compiler Condition Lowering Specification

## Purpose

The compiler is the sole place reference resolution happens: authoring `Project` data becomes a
`RuntimeProfile` with concrete entry IDs and typed conditions. Today every `Condition` action
shortcuts to `RuntimeCondition::AlwaysTrue` (compiler/src/lib.rs:157-161) and `LootObject` always
emits `object_entry: 0`. This capability makes lowering real: typed conditions, resolved object
entries, and resolution against a live QueryServer so re-imported sample projects become
trustworthy golden artifacts.

## Requirements

### Requirement: Condition Lowering Completeness

The compiler MUST translate every authoring `Condition` expression attached to an action into the
matching typed `RuntimeCondition` variant (`QuestAccepted`, `QuestCompleted`, `ItemCountAtLeast`,
`LevelAtLeast`, etc.), and MUST NOT default to `AlwaysTrue` as a blanket fallback. Expressions that
cannot be mapped to any known predicate MUST be recorded as a compiler diagnostic identifying the
unmapped expression and the action it was attached to.

#### Scenario: Recognized condition expression

- GIVEN an authoring condition expression referencing quest completion for quest `1234`
- WHEN the compiler lowers the owning action
- THEN the emitted `RuntimeAction::Condition` MUST contain `RuntimeCondition::QuestCompleted(1234)`

#### Scenario: Unrecognized condition expression

- GIVEN a condition expression matching no known predicate grammar
- WHEN the compiler lowers the owning action
- THEN the compiler MUST record a diagnostic identifying the unmapped expression, and MUST NOT
  silently substitute `AlwaysTrue` without that diagnostic

### Requirement: LootObject Entry Resolution

The compiler MUST resolve the target world object's numeric entry for `LootObject` actions from
the authoring reference (via the resolved object library or an explicit entry reference), and MUST
NOT emit `object_entry: 0` as a placeholder.

#### Scenario: Resolvable loot object

- GIVEN a `LootObject` action referencing a known object
- WHEN the compiler lowers it
- THEN `RuntimeLoot.object_entry` MUST equal the resolved entry, not `0`

#### Scenario: Unresolvable loot object

- GIVEN a `LootObject` action whose reference cannot be resolved
- WHEN the compiler lowers it
- THEN the compiler MUST emit a diagnostic rather than silently emitting `object_entry: 0`

### Requirement: Resolution Against a Live QueryServer

The import → compile pipeline MUST run against a live QueryServer instance (not an empty/mock
client) so NPC, quest, and object references resolve to concrete IDs and coordinates. References
that remain unresolved after live lookup MUST surface as diagnostics, never as silently zeroed or
defaulted values.

#### Scenario: Live resolution succeeds

- GIVEN a guide referencing an NPC present in the live QueryServer database
- WHEN the project is (re-)imported
- THEN the NPC library entry MUST carry the resolved entry ID, and dependent actions
  (`AcceptQuest`, `Vendor`, etc.) MUST reference that resolved NPC, not a `Comment` downgrade

### Requirement: Compile-Time Class Restriction Filtering

The compiler MUST accept a target class parameter and MUST exclude from the emitted
`RuntimeProfile` every action or operation whose class restriction (parsed from per-line
`<< Class` suffixes or step-level restrictions) does not match the target class. Class
restrictions MUST NOT be forwarded to the runtime for evaluation: a compiled profile contains
only actions applicable to its target class, keeping the runtime free of class-decision logic.
Excluded actions MUST be counted in the compile report (not silently vanish).

#### Scenario: Non-matching class-gated action excluded

- GIVEN a project containing an action restricted to `Paladin` and a compile target class of `Warrior`
- WHEN the project is compiled
- THEN the emitted `RuntimeProfile` MUST NOT contain that action, and the compile report MUST
  count it as class-excluded

#### Scenario: Matching class-gated action retained

- GIVEN the same project and a compile target class of `Paladin`
- WHEN the project is compiled
- THEN the emitted `RuntimeProfile` MUST contain the action with no class-restriction metadata
  attached

### Requirement: Golden Artifact Regeneration with Corpus Coverage Statistics

Re-running import against the live QueryServer MUST regenerate every sample project under
`.questing/projects/` as a golden artifact, and the pipeline MUST report corpus-wide coverage
statistics (share of commands lowered to typed actions/conditions vs. inert-preserved vs. any
remaining unresolved) validated against the fidelity bar defined by the proposal.

#### Scenario: Full corpus re-import

- GIVEN all existing sample guides and a live QueryServer
- WHEN the import pipeline is re-run
- THEN every regenerated project JSON MUST replace its prior golden artifact, and a coverage
  report MUST be produced showing the percentage of commands typed/resolved

#### Scenario: Regression check on Elwynn sample

- GIVEN the previously-broken Elwynn Forest sample (777 Comments, 0 AcceptQuest)
- WHEN it is re-imported against the live QueryServer
- THEN the regenerated project MUST contain resolved `AcceptQuest`/`TurnInQuest` actions rather
  than blanket `Comment` downgrades
