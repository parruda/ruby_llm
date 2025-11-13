# Changelog

All notable changes to RubyLLM will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- **Multi-Subscriber Callback System**: Register multiple callbacks for the same event using `on_new_message`, `on_end_message`, `on_tool_call`, and `on_tool_result`. Callbacks fire in FIFO order with error isolation.
- **Subscription Management**: New `subscribe(event, tag:)` method returns a `Subscription` object that can be unsubscribed later. Added `once(event)` for one-time callbacks.
- **Thread-Safe Message Management**: Added `@messages_mutex` for thread-safe message operations. New methods: `message_history`, `set_messages`, `snapshot_messages`, `restore_messages`, `reset_messages!`.
- **Concurrent Tool Execution**: Configure parallel tool execution with `with_tool_concurrency(:async, max: 5)` or `with_tool_concurrency(:threads, max: 10)`.
- **Tool Executor Registry**: New `RubyLLM.register_tool_executor(name)` API for custom executors. Built-in `:async` (fiber-based) and `:threads` (stdlib) executors.
- **Message Transaction Support**: `with_message_transaction` block for atomic operations with rollback on failure.
- **Extensibility Hook**: `around_tool_execution` hook for subclasses to add caching, rate limiting, instrumentation, etc.
- **Utility Methods**: `callback_count`, `clear_callbacks`, `tool_results_complete?`, `repair_incomplete_tool_calls!`.

### Changed

- `on_new_message`, `on_end_message`, `on_tool_call`, `on_tool_result` now append callbacks instead of replacing them (backward compatible - single callback still works as before).
- Tool execution refactored into smaller, composable methods for better maintainability.
- ActiveRecord integration simplified to delegate callbacks properly without accessing internal state.

### Fixed

- ActiveRecord `on_new_message` and `on_end_message` no longer use `instance_variable_get` to access internal callback state.
