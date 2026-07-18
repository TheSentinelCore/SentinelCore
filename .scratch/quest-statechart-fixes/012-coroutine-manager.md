---
id: 12
title: "Architecture: Structured Concurrency with CoroutineManager"
state: open
labels: ["enhancement", "ready-for-agent", "area:quest", "architecture"]
created: "2026-07-16T10:00:00Z"
updated: "2026-07-16T10:00:00Z"
---

## Description

Implement structured concurrency for async profile actions. The current `awaitEvent` pattern has no cancellation mechanism, causing subscription leaks and potential zombie coroutine resumption.

## Background

Per ADR-0004: "Lua coroutine management for async actions must be robust (timeouts, cancellation on state exit)."

Current issues:
- Subscriptions created in `_runActions` are not tracked
- `_cancelStateActions` doesn't unsubscribe from eventBus
- No cancellation signal sent to awaiting coroutines

## Acceptance Criteria

- [ ] CoroutineManager module created to track lifecycle
- [ ] All active coroutines tracked by stateId
- [ ] Subscriptions tracked per state and cleaned on exit
- [ ] Cancelled coroutine flag prevents zombie resumption
- [ ] Timeout handling works for abandoned waits