# Delta for editor-web-ui

## ADDED Requirements

### Requirement: Project list and management

The UI MUST list projects with operation counts and provide create, open, rename, duplicate, and delete via the project endpoints; delete MUST require confirmation first.

#### Scenario: Open a project

- GIVEN projects exist, WHEN the user selects "alpha", THEN it loads and its operations view shows

#### Scenario: Delete requires confirmation

- WHEN the user starts delete on "beta" then cancels, THEN no request is sent

### Requirement: Operation list editing

The UI MUST show operations in order with add, remove, enable toggle, and reorder via move-operation; the view MUST refresh from returned project JSON.

#### Scenario: Reorder an operation

- GIVEN operations [A, B, C], WHEN the user moves A below C, THEN the UI calls move-operation from=0, to=2 and displays [B, C, A]

#### Scenario: Toggle operation enabled

- WHEN the user disables operation B, THEN the UI issues modify-operation with enabled=false

### Requirement: Action editing within an operation

The UI MUST list the selected operation's actions with add-by-type via a per-type payload-form registry covering all action types, remove, modify-action field edits, enable toggle, and raw-string condition editing.

#### Scenario: Add an action by type

- WHEN the user adds an "AcceptQuest" action, THEN the UI issues add-action with a valid default payload and the action appears

#### Scenario: Edit condition as raw string

- WHEN the user sets an action's condition to "level >= 10", THEN the UI issues modify-action carrying that exact string

### Requirement: Validation view

The UI MUST run validation on demand, group diagnostics by severity, and select the referenced operation or action when a diagnostic is clicked.

#### Scenario: Grouping and navigation

- GIVEN validation returns errors and a warning, one referencing operation "Goldshire", WHEN the user clicks that diagnostic, THEN diagnostics render grouped by severity and "Goldshire" is selected

### Requirement: Compile view

The UI MUST run compilation on demand, show operation count and diagnostics, and on success offer download and clipboard copy of the runtime JSON; on failure it MUST display the error and offer no download.

#### Scenario: Compile and download

- GIVEN a loaded valid project, WHEN the user compiles, THEN count and diagnostics show and the runtime JSON can be downloaded or copied

### Requirement: Query browser and reference insertion

The UI MUST provide NPC and quest text search and NPC/quest/object detail via /editor/query/*, inserting a selected entity's reference into the edited action field.

#### Scenario: Search and insert a reference

- GIVEN an action field expecting a quest reference, WHEN the user searches "thomas", picks one, and confirms, THEN the field is populated from it

### Requirement: Console log view

Every user-initiated action (load, save, edit command, validate, compile) MUST append a timestamped success-or-failure entry to a console view.

#### Scenario: Action feedback logged

- WHEN the user saves then runs a failing request, THEN timestamped success and failure entries appear

### Requirement: Dirty state and unload protection

Because command edits persist to disk per command, the UI MUST treat as dirty only (a) inspector form edits not yet Applied, or (b) an edit whose persist request failed. The UI MUST indicate dirty state, clear it on Apply/successful persist, and prompt before unload only while dirty.

#### Scenario: Unload prompt while dirty

- GIVEN an unapplied inspector form edit (or a failed persist), WHEN the user tries to close or reload the tab, THEN the browser's beforeunload prompt triggers

#### Scenario: Successful command edit is not dirty

- GIVEN an action edit confirmed by a successful command response, WHEN the user closes the tab, THEN no unload prompt appears

### Requirement: Empty states

Views with no data MUST render an explicit empty state with a next action: no projects, no loaded project, empty operation, no diagnostics.

#### Scenario: No projects exist

- GIVEN a server with zero projects, THEN the project list shows an empty state prompting creation

### Requirement: Error surfacing

Any failed request MUST show a visible message — the server's `error` body when present, else a generic description. No failure MAY be silent.

#### Scenario: Command error displayed

- WHEN a command endpoint returns 404 "not loaded", THEN the UI displays the message
