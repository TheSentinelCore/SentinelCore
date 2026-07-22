# Delta for editor-server-api

## ADDED Requirements

### Requirement: Command endpoints persist to disk

After each successful command, the six command endpoints (add/remove/modify-operation, add/remove/modify-action) MUST persist the project to disk before responding with the full updated project JSON. A failed write MUST return an error, never success.

#### Scenario: Command edit survives server restart

- GIVEN project "alpha" is loaded
- WHEN an operation is added via add-operation and the server restarts
- THEN loading "alpha" returns a project containing that operation

#### Scenario: Persistence failure is an error

- GIVEN the projects directory is unwritable
- WHEN a command's disk write fails
- THEN the response is a 5xx error

### Requirement: Full save preserves undo history

PUT /editor/projects/{name} MUST persist the submitted project and update the session project, but MUST NOT reset the session's command history; pre-save commands MUST remain undoable.

#### Scenario: Undo works across a full save

- GIVEN "alpha" is loaded and an operation was added via command endpoint
- WHEN the client saves via PUT and then calls undo
- THEN the undo succeeds and the added operation is removed

### Requirement: Move operation endpoint

POST /editor/projects/{name}/move-operation MUST accept 0-based `{from, to}` indices, reject out-of-range values with 400, and on success record the move in command history (undoable) and persist to disk.

#### Scenario: Reorder with undo

- GIVEN operations [A, B, C]
- WHEN the client posts {from: 0, to: 2} and then calls undo
- THEN the order becomes [B, C, A], and undo restores [A, B, C]

#### Scenario: Out-of-range index rejected

- GIVEN a project with 3 operations
- WHEN the client posts {from: 0, to: 3}
- THEN the response is 400 and the project is unchanged

### Requirement: QueryServer proxy routes

The server MUST proxy GET /editor/query/ routes to the QueryServer via sentinel-queryclient, returning upstream JSON unchanged: NPC and quest search+detail, object detail. Upstream outcomes MUST map to: not-found 404, transport/upstream failure 502.

#### Scenario: Search is forwarded

- GIVEN the QueryServer is running
- WHEN the client requests GET /editor/query/npc/search?q=thomas
- THEN the response is the upstream NPC summary JSON array

#### Scenario: Upstream failures map to status codes

- WHEN a detail lookup misses upstream, THEN the proxy responds 404
- WHEN the QueryServer is unreachable, THEN /editor/query/* requests respond 502

### Requirement: Static SPA serving

The server MUST serve the SPA same-origin: GET / returns index.html; asset paths return files with correct content types; other GET paths outside /editor and /health MUST fall back to index.html. With SENTINEL_EDITOR_UI_DIR set, assets MUST come from that directory, not the embedded bundle.

#### Scenario: Client-route fallback

- WHEN a browser requests GET /projects/alpha/validate
- THEN the response is index.html with status 200

#### Scenario: Dev override serves from disk

- GIVEN SENTINEL_EDITOR_UI_DIR is set
- WHEN an asset is edited on disk and re-requested
- THEN the updated content is served without a rebuild

### Requirement: Consistent error response shape

All /editor/* endpoints MUST return errors as JSON with an `error` message field (MAY add a stable `code`). Status MUST match: 400 invalid input, 404 unknown/unloaded project, 409 conflict, 502 upstream failure, 500 otherwise.

#### Scenario: Unloaded project command error

- WHEN a command endpoint targets a project with no loaded session
- THEN the response is 404 with a JSON `error` message, never HTML or empty

### Requirement: Compile and validate reflect persisted state

POST compile and /validate MUST retain their existing contracts (CompileResult; Diagnostic array) and MUST operate on the latest command-made edits without an explicit full save.

#### Scenario: Compile sees command-made edits

- GIVEN an operation was added via command endpoint without a full save
- WHEN the client compiles
- THEN the CompileResult includes the new operation

#### Scenario: Unknown project still 404

- WHEN compile or validate targets a nonexistent project
- THEN the response is 404 in the standard error shape
