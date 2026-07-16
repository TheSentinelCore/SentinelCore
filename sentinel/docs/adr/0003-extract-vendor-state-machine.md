# ADR-0003: Extract VendorStateMachine from Vendor Phase

The Vendor phase (modules/grind/phases/vendor.lua) contained a 9-state machine inline inside a single BT action function, managed through 5+ blackboard keys. Extracted into a dedicated VendorStateMachine module with a deep interface (tick, reset, is_running) that owns its state internally.

## Considered Options

1. **Keep inline** — rejected. The state machine was shallow: understanding one state required tracing all 9 transitions through indirect blackboard writes.

2. **Extract VendorStateMachine** — selected. Same pattern as ADR-0001 (ConsumeManager). Internal state, blackboard-free interface, testable in isolation.

3. **Generic StateMachine** — rejected as over-abstraction. Vendor interactions have unique semantics (vendor window timing, HTTP quality lookups, repair/sell/buy sequence) that don't generalize to other phases.
