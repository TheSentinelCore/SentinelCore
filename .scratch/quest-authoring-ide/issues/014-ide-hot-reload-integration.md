# 014 — IDE: Hot-Reload Integration

**What to build:** Implement the hot-reload system that allows the IDE to update the running executor without restarting:
- File watcher monitors project YAML files for changes
- On save, triggers compilation and notifies executor of update
- Executor preserves current state (variables, position, active quests, combat state) during swap
- Visual feedback in IDE: "Reloading..." status, success/error notifications
- Configurable delay (debounce) to prevent excessive recompilation during typing
- Option to disable auto-reload for manual control
- Integration with Validation panel: shows compilation errors before attempting reload
- Fallback mechanism: if reload fails, revert to previous version and notify user
- Performance tracking: measures compile time and swap time
- Security: validates incoming update requests to prevent malicious code
- Logging: detailed logs of reload process for debugging
- Support for multiple simultaneous clients (if debugging multiple characters)
- Version checking: prevents loading incompatible compiler/runtime versions
- Atomic updates: prevents partial updates during the swap process
- Memory leak detection: monitors for accumulated objects during frequent reloads
- Graceful degradation: if hot-reload fails, falls back to full restart with warning
- Integration with IDE status bar: shows last reload time and status
- Configurable retry mechanism for failed reloads (with exponential backoff)
- Detailed error reporting: what failed and why during the reload process
- Option to preserve UI state (scroll positions, selected items) during reload
- Integration with Profiling: optionally run performance tests after reload
- Support for selective reload: only update changed operations if possible
- Clear distinction between development and production reload behavior
- Choose communication mechanism: WebSocket for low latency, HTTP for simplicity, or IPC for in-process
- Message queue system to handle rapid-fire save events
- Health check endpoint: returns status and version info
- Rate limiting: max 1 request per 500ms per IP
- Add SSL/TLS configuration options (certificates, keys, CA) if using network communication
- Configure IPC security: validate message authenticity and integrity if using inter-process communication
- Comprehensive test suite for reload scenarios (network loss, invalid data, etc.)

**Blocked by:** 001 — Source Format Specification

**Status:** ready-for-agent

- [ ] Create file watcher component (using chokidar or native FS events)
- [ ] Implement debounced save triggering (e.g., 500ms delay after last change)
- [ ] Design message protocol between IDE and executor (JSON over WebSocket/HTTP/IPC)
- [ ] Add validation step before compiling: prevent reload on syntax errors
- [ ] Integrate with Validation panel to show compile errors first
- [ ] Implement executor notification endpoint (HTTP POST or WebSocket message or IPC call)
- [ ] Add state preservation logic: serialize variables, position, quests before swap
- [ ] Create visual feedback: spinner, success checkmark, error X
- [ ] Make auto-reload toggleable in settings (default: enabled)
- [ ] Add manual reload button for when auto-disabled
- [ ] Track and display timing: compile time, network time, swap time
- [ ] Implement HMAC or similar for message authentication (if security needed)
- [ ] Add detailed logging: what was sent, when, response received
- [ ] Support multiple clients connecting to same executor (different chars)
- [ ] Add version handshake: client and server exchange version numbers
- [ ] Use temporary files and atomic rename for safe updates
- [ ] Implement fallback: on failure, show error and offer full restart option
- [ ] Integrate with IDE status bar: show "Last updated: 2m ago" or "Error: ..."
- [ ] Add retry mechanism: 3 attempts with increasing delays (1s, 2s, 4s)
- [ ] Include detailed error info: validation failure, timeout, server error
- [ ] Add option to freeze UI state during reload (preserve scroll/selection)
- [ ] Integrate with Profiler: optional performance validation after reload
- [ ] Add feature flags: enable/disable specific reload optimizations
- [ ] Implement selective reload: only update changed operations if possible
- [ ] Clearly separate dev vs prod behavior: dev warns, prod fails fast
- [ ] Choose communication mechanism: WebSocket for low latency, HTTP for simplicity, or IPC for in-process
- [ ] Implement message queue: buffer rapid saves, process at intervals
- [ ] Add health check endpoint: returns status and version info
- [ ] Set rate limits: max 1 request per 500ms per IP
- [ ] Add SSL/TLS configuration options (certificates, keys, CA) if using network communication
- [ ] Configure IPC security: validate message authenticity and integrity if using inter-process communication
- [ ] Create test harness: simulate various failure conditions and recovery
- [ ] Document API: exact message formats, error codes, expected behaviors