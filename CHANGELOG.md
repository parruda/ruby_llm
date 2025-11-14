# Changelog

All notable changes to RubyLLM will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- **OpenAI Responses API Support**: Native support for OpenAI's new `v1/responses` endpoint. Enable with `chat.with_responses_api(stateful: true)` for efficient multi-turn conversations. Features include:
  - Stateful conversations with automatic `previous_response_id` tracking for token efficiency
  - Session persistence via `ResponsesSession` with TTL management and failure recovery
  - Reasoning insights through `response.reasoning_summary` and `response.reasoning_tokens`
  - Clean provider inheritance pattern with `OpenAIResponses < OpenAI`
  - Automatic retry on response ID expiration with configurable failure limits
  - Support for structured output, truncation, service tiers, and custom includes
- **Multi-Subscriber Callback System**: Register multiple callbacks for the same event using `on_new_message`, `on_end_message`, `on_tool_call`, and `on_tool_result`. Callbacks fire in FIFO order with error isolation.
- **Subscription Management**: New `subscribe(event, tag:)` method returns a `Subscription` object that can be unsubscribed later. Added `once(event)` for one-time callbacks.
- **Thread-Safe Message Management**: Added `@messages_mutex` for thread-safe message operations. New methods: `message_history`, `set_messages`, `snapshot_messages`, `restore_messages`, `reset_messages!`.
- **Concurrent Tool Execution**: Configure parallel tool execution with `with_tool_concurrency(:async, max: 5)` or `with_tool_concurrency(:threads, max: 10)`.
- **Tool Executor Registry**: New `RubyLLM.register_tool_executor(name)` API for custom executors. Built-in `:async` (fiber-based) and `:threads` (stdlib) executors.
- **Message Transaction Support**: `with_message_transaction` block for atomic operations with rollback on failure.
- **Utility Methods**: `callback_count`, `clear_callbacks`, `tool_results_complete?`, `repair_incomplete_tool_calls!`.
- **Around Tool Execution Hook**: New `around_tool_execution` method for wrapping tool execution with custom behavior (caching, rate limiting, instrumentation). Uses composition pattern instead of subclassing.
- **Responses API Error Classes**: New error hierarchy including `ResponsesApiError`, `ResponseIdNotFoundError`, `ResponseFailedError`, `ResponseInProgressError`, `ResponseCancelledError`, and `ResponseIncompleteError`.
- **Message Attributes**: Added `response_id`, `reasoning_summary`, and `reasoning_tokens` to `Message` class for Responses API metadata.

### Changed

- `on_new_message`, `on_end_message`, `on_tool_call`, `on_tool_result` now append callbacks instead of replacing them (backward compatible - single callback still works as before).
- `on_tool_result` callback now receives both `tool_call` and `result` arguments instead of just `result`.
- `reset_messages!` now preserves system prompts by default. Use `reset_messages!(preserve_system_prompt: false)` to clear everything.
- `around_tool_execution` changed from subclass-override pattern to settable callback block. The hook now receives `(tool_call, tool_instance, execute_proc)` instead of `(tool_call, tool_instance:)` with yield.
- Tool execution refactored into smaller, composable methods for better maintainability.
- ActiveRecord integration simplified to delegate callbacks properly without accessing internal state.

### Fixed

- ActiveRecord `on_new_message` and `on_end_message` no longer use `instance_variable_get` to access internal callback state.
