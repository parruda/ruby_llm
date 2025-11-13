# Chat-Level Tool Concurrency with Extensibility Hook

## Intent

**Why this feature?**

When LLMs request multiple tool calls in a single response (e.g., "Get weather for NYC, stock price for AAPL, and currency rate for EUR/USD"), executing them sequentially is inefficient. A 3-tool call that takes 2s, 3s, and 1s respectively takes 6 seconds sequentially, but only 3 seconds when executed concurrently.

**Why chat-level configuration?**

Concurrent execution is an **execution strategy** decision, not a **tool selection** decision. It should be configured once at the Chat level, not mixed into tool registration. This provides clear semantics and separation of concerns.

**Why the extensibility hook?**

Users and downstream libraries need to customize tool execution behavior without overriding entire methods. Common use cases:
- **Rate limiting**: Prevent API quota exhaustion
- **Caching**: Return cached results for repeated calls
- **Instrumentation**: Track timing and performance
- **Circuit breakers**: Fail fast when services are down
- **Resource pooling**: Manage database connections

The `around_tool_execution` hook follows Rails conventions (`around_action`) and provides maximum flexibility with minimal API surface.

---

## Summary

This proposal introduces concurrent tool execution in RubyLLM with two key features:
1. **Chat-level configuration** - Configure concurrency at chat initialization, not tool registration
2. **Extensibility hook** - `around_tool_execution` method for customizing tool execution behavior

## API Design

### Constructor Parameters

```ruby
chat = RubyLLM.chat(
  model: "claude-sonnet-4",
  tool_concurrency: :async,
  max_concurrency: 5
)
```

### Chainable Method

```ruby
chat = RubyLLM.chat
  .with_tool_concurrency(:async, max: 5)
  .with_tools(Weather, StockPrice, Currency)
```

### Extensibility Hook

```ruby
# Override in subclass for custom behavior
def around_tool_execution(tool_call, tool_instance:)
  yield  # Default: just execute
end
```

## Why Chat-Level Configuration?

The original proposal ties concurrency to tool selection:
```ruby
# Original (confusing semantics)
chat.with_tools(Weather, StockPrice, concurrency: :async, max_concurrency: 5)
```

**Problems:**
- Does adding more tools later change concurrency mode?
- What if different `with_tools` calls have different settings?
- Concurrency is about **how** tools execute, not **which** tools

**Better approach:**
```ruby
# Clear: "This chat runs tools concurrently"
chat = RubyLLM.chat(tool_concurrency: :async)
chat.with_tools(A, B, C)  # Just tool registration
```

Separation of concerns: Tool selection ≠ execution strategy

## Core Implementation

### Chat Class Changes

```ruby
class Chat
  attr_reader :tool_concurrency, :max_concurrency

  def initialize(model:, tool_concurrency: nil, max_concurrency: nil, **options)
    @tool_concurrency = tool_concurrency
    @max_concurrency = max_concurrency
    # ... existing initialization
  end

  def with_tool_concurrency(mode = nil, max: nil)
    @tool_concurrency = mode unless mode.nil?
    @max_concurrency = max if max
    self
  end

  def handle_tool_calls(response, &block)
    halt_result = if concurrent_tools?
                    execute_tools_concurrently(response.tool_calls)
                  else
                    execute_tools_sequentially(response.tool_calls)
                  end

    halt_result || complete(&block)
  end

  private

  def concurrent_tools?
    @tool_concurrency && @tool_concurrency != :sequential
  end
end
```

### Sequential Execution (Current Behavior)

```ruby
def execute_tools_sequentially(tool_calls)
  halt_result = nil

  tool_calls.each_value do |tool_call|
    result = execute_single_tool_with_message(tool_call)
    halt_result = result if result.is_a?(Tool::Halt)
  end

  halt_result
end
```

### Concurrent Execution (Hybrid Pattern)

The hybrid pattern fires events immediately for progress feedback, but adds messages atomically to ensure Chat state consistency:

```ruby
def execute_tools_concurrently(tool_calls)
  # Phase 1: Execute tools concurrently with immediate event feedback
  results = parallel_execute_tools(tool_calls)

  # Phase 2: Add messages atomically (ensures valid Chat state)
  add_tool_results_atomically(tool_calls, results)

  # Return first halt by REQUEST order (not completion order)
  halt_result = nil
  tool_calls.each_key do |id|
    result = results[id]
    if result.is_a?(Tool::Halt) && halt_result.nil?
      halt_result = result
    end
  end

  halt_result
end

def parallel_execute_tools(tool_calls)
  executor = RubyLLM.tool_executors[@tool_concurrency]
  raise ArgumentError, "Unknown executor: #{@tool_concurrency}" unless executor

  executor.call(tool_calls.values, max_concurrency: @max_concurrency) do |tool_call|
    execute_single_tool_with_events(tool_call)
  end
end

def add_tool_results_atomically(tool_calls, results)
  messages = []

  # Add ALL messages in a single synchronized block
  # This ensures Chat state is always valid (no partial results)
  @messages_mutex.synchronize do
    tool_calls.each_key do |id|
      tool_call = tool_calls[id]
      result = results[id]

      tool_payload = result.is_a?(Tool::Halt) ? result.content : result
      content = content_like?(tool_payload) ? tool_payload : tool_payload.to_s
      message = Message.new(role: :tool, content:, tool_call_id: tool_call.id)
      @messages << message
      messages << message
    end
  end

  # Fire events OUTSIDE mutex (better performance, no blocking)
  # This prevents slow callbacks from holding the mutex
  messages.each { |msg| emit(:end_message, msg) }
end
```

### Single Tool Execution (Shared)

```ruby
# For sequential execution - fires all events and adds message immediately
def execute_single_tool_with_message(tool_call)
  emit(:new_message)
  result = execute_single_tool(tool_call)
  message = add_tool_result_message(tool_call, result)
  emit(:end_message, message)
  result
end

# For concurrent execution - fires events but doesn't add message (atomic later)
def execute_single_tool_with_events(tool_call)
  emit(:new_message)
  result = execute_single_tool(tool_call)
  emit(:tool_result, result)
  result
end

# Core tool execution - fires tool_call event, executes tool
def execute_single_tool(tool_call)
  emit(:tool_call, tool_call)

  tool_instance = tools[tool_call.name.to_sym]
  result = around_tool_execution(tool_call, tool_instance:) do
    tool_instance.call(tool_call.arguments)
  end

  result
end

def add_tool_result_message(tool_call, result)
  tool_payload = result.is_a?(Tool::Halt) ? result.content : result
  content = content_like?(tool_payload) ? tool_payload : tool_payload.to_s
  add_message(role: :tool, content:, tool_call_id: tool_call.id)
end
```

### Thread-Safe Message Addition

Since messages may be added concurrently (and for atomic addition), `add_message` must be thread-safe:

```ruby
def initialize(...)
  @messages = []
  @messages_mutex = Mutex.new
  # No savepoint stack needed - index-based transactions use local variables
  # ...
end

def add_message(message_or_attributes)
  message = message_or_attributes.is_a?(Message) ? message_or_attributes : Message.new(**message_or_attributes)
  @messages_mutex.synchronize do
    @messages << message  # Use @messages directly, NOT the getter!
  end
  message
end
```

**CRITICAL**: The current RubyLLM code has `messages << message` which uses the **public getter**. This must change to `@messages << message` for thread safety.

**Note**: The Mutex protects both individual message additions (sequential) and atomic batch additions (concurrent).

### Message Management API

Users need safe ways to read, replace, and snapshot messages:

```ruby
class Chat
  # Returns the live messages array for backwards compatibility.
  #
  # WARNING: Direct mutation of this array is NOT thread-safe!
  # - DO NOT use: chat.messages << msg (bypasses mutex)
  # - DO NOT use: chat.messages.pop (bypasses mutex)
  # - DO NOT use: chat.messages.clear (bypasses mutex)
  #
  # Instead use:
  # - chat.add_message(msg) for appending
  # - chat.set_messages(array) for replacing
  # - chat.reset_messages! for clearing
  # - chat.message_history for safe reading (frozen copy)
  # - chat.snapshot_messages for checkpointing
  #
  # Reading is safe: chat.messages.each, chat.messages.size, etc.
  attr_reader :messages

  # NEW: Safe read-only snapshot (thread-safe)
  # Returns a frozen copy of the messages array
  def message_history
    @messages_mutex.synchronize { @messages.dup.freeze }
  end

  # NEW: Thread-safe replacement
  def set_messages(new_messages)
    @messages_mutex.synchronize do
      @messages.clear
      new_messages.each do |msg|
        @messages << (msg.is_a?(Message) ? msg : Message.new(**msg))
      end
    end
    self
  end

  # NEW: Snapshot for checkpointing (thread-safe)
  def snapshot_messages
    @messages_mutex.synchronize { @messages.map(&:dup) }
  end

  # NEW: Restore from snapshot (thread-safe)
  def restore_messages(snapshot)
    set_messages(snapshot)
  end

  # UPDATED: Thread-safe reset
  def reset_messages!
    @messages_mutex.synchronize { @messages.clear }
    self
  end
end
```

**User Scenarios:**

```ruby
# Read messages safely (frozen copy)
history = chat.message_history
history.each { |m| puts m.content }

# Replace entire history
saved = database.load_messages(chat_id)
chat.set_messages(saved)

# Checkpoint and restore
checkpoint = chat.snapshot_messages
begin
  chat.ask("Risky operation")
rescue
  chat.restore_messages(checkpoint)
end

# Clear and start over
chat.reset_messages!

# Direct access (backwards compatible, not thread-safe)
chat.messages.each { |m| ... }  # OK for reading
chat.messages << msg  # At your own risk! Use add_message instead
```

**Backwards Compatibility:**
- `chat.messages` still returns the live array (no breaking change)
- Direct mutation bypasses mutex (documented as "at your own risk")
- New APIs (`message_history`, `set_messages`, etc.) are thread-safe
- Future version could deprecate direct mutation

### Message Transaction Support (Critical for Cancellation Safety)

**The Problem**: The assistant message with `tool_calls` is added BEFORE tools execute. If cancelled, Chat is left in invalid state.

```ruby
def complete(&block)
  response = @provider.complete(...)
  add_message response  # ← Assistant message ADDED HERE

  if response.tool_call?
    handle_tool_calls(response, &block)  # ← Cancellation happens HERE
  end
end

# After cancellation:
@messages = [
  user: "Process tasks",
  assistant: { tool_calls: [A, B, C] }  # ADDED
  # NO TOOL RESULTS! Invalid for LLM API
]
```

**Solution: Index-Based Transaction (Simple & Efficient)**

Since messages are **append-only** during tool execution, we just track the index:

```ruby
class Chat
  def initialize(...)
    @messages = []
    @messages_mutex = Mutex.new
    # No savepoint stack needed - just track index
  end

  # Wrap operations in transaction for rollback on failure
  def with_message_transaction
    start_index = @messages_mutex.synchronize { @messages.size }

    begin
      yield
    rescue => e
      # Truncate back to where we started (O(1) operation)
      @messages_mutex.synchronize do
        @messages.slice!(start_index..-1)
      end
      raise
    end
  end
end
```

**Why index-based is better:**

| Aspect | Array.dup (old) | Index tracking (new) |
|--------|-----------------|---------------------|
| Memory | O(n) - copy entire array | O(1) - just an integer |
| Savepoint | `@messages.dup` | `@messages.size` |
| Rollback | `@messages.replace(savepoint)` | `@messages.slice!(start..-1)` |
| Complexity | Savepoint stack management | Local variable |
| Thread safety | Must protect array copy | Simple index read |

**Wrap Tool Execution in Transaction:**

```ruby
def complete(&block)
  response = @provider.complete(...)
  emit(:new_message) unless block_given?

  if response.tool_call?
    execute_tool_call_sequence(response, &block)  # Transactional
  else
    add_message response
    emit(:end_message, response)
    response
  end
end

def execute_tool_call_sequence(response, &block)
  with_message_transaction do
    # Add assistant message (inside transaction)
    add_message response
    emit(:end_message, response)

    # Execute tools
    halt_result = if concurrent_tools?
                    execute_tools_concurrently(response.tool_calls)
                  else
                    execute_tools_sequentially(response.tool_calls)
                  end

    halt_result || complete(&block)  # Recurse for more tool calls
  end
end
```

**Even simpler inline version (no helper method):**

```ruby
def execute_tool_call_sequence(response, &block)
  start_index = @messages.size

  begin
    add_message response
    emit(:end_message, response)

    halt_result = if concurrent_tools?
                    execute_tools_concurrently(response.tool_calls)
                  else
                    execute_tools_sequentially(response.tool_calls)
                  end

    halt_result || complete(&block)
  rescue => e
    @messages_mutex.synchronize { @messages.slice!(start_index..-1) }
    raise
  end
end
```

**Benefits:**
- ✅ Cancellation rolls back assistant message + any partial results
- ✅ Chat state always valid (no incomplete tool_calls)
- ✅ Safe for Async::Stop, exceptions, or any error
- ✅ O(1) memory overhead (just an integer, no array copy)
- ✅ Simple implementation (no savepoint stack)
- ✅ LLM API calls always accept the conversation
- ✅ Nested transactions work naturally (each has its own start_index)

### Extensibility Hook

```ruby
# Extensibility hook for wrapping tool execution.
# Override to add resource management, caching, instrumentation, etc.
#
# Can short-circuit by not calling yield and returning a value directly.
# Must be exception-safe (use ensure for cleanup).
#
# @param tool_call [ToolCall] The tool call being executed
# @param tool_instance [Tool] The tool instance
# @yield Executes the actual tool
# @return [Object] Tool result (from yield or short-circuit)
def around_tool_execution(tool_call, tool_instance:)
  yield
end
```

## Why Hybrid Pattern?

The hybrid pattern balances immediate feedback with Chat state consistency:

**Immediate event feedback (tool_call, tool_result, new_message):**
- Events fire as soon as each tool completes (not batched)
- Subscribers see real-time progress
- Better user experience (see results immediately)

**Atomic message addition (end_message):**
- All tool result messages added together after all tools complete
- Chat state is always valid (no partial results)
- Safe for cancellation/interruption
- LLM APIs accept the conversation

**Performance where it matters:**
```
Sequential:  [Tool A: 2s] → [Tool B: 3s] → [Tool C: 1s] = 6s total
Concurrent:  [Tool A: 2s] → fires tool_call/tool_result immediately
             [Tool B: 3s] → fires events as it finishes (3s mark)
             [Tool C: 1s] → fires events immediately
             [All complete] → add all messages atomically, fire end_message events
             Total: 3s (3x faster!)
```

**Thread-safe by design:**
- `@messages` array protected by Mutex
- Atomic batch addition ensures consistency
- Events fire immediately without blocking other tools

**Trade-offs:**
- `end_message` events fire after ALL tools complete (not immediately per tool)
- Message order in array matches request order (atomic addition iterates in order)
- Slight delay before messages appear in Chat history

**Why this is better than pure fire-as-complete:**
- ✅ Chat state is always valid (critical for API calls)
- ✅ Safe for cancellation (no partial results)
- ✅ No rollback logic needed
- ✅ Still get immediate progress via `tool_call`/`tool_result`
- ✅ LLM APIs always accept the conversation

**For real-time progress**, subscribe to `tool_call` and `tool_result` events. For message-level tracking, subscribe to `end_message` (fires after all tools complete).

## Registry Pattern for Executors

```ruby
module RubyLLM
  @tool_executors = {}

  def self.register_tool_executor(name, &block)
    @tool_executors[name] = block
  end

  def self.tool_executors
    @tool_executors
  end
end
```

### Built-in Executors

RubyLLM ships with two built-in executors. Both use **only Ruby stdlib** - no external dependencies.

#### Async Executor (Fibers)

Uses the `async` gem for lightweight fiber-based concurrency. Uses `Async::Barrier` to ensure all tasks complete even if some fail.

```ruby
RubyLLM.register_tool_executor(:async) do |tool_calls, max_concurrency:, &execute|
  require 'async'
  require 'async/barrier'
  require 'async/semaphore'
  require 'kernel/sync'  # For Sync method

  Sync do  # Use Sync, not Async{}.wait - more idiomatic and efficient
    semaphore = max_concurrency ? Async::Semaphore.new(max_concurrency) : nil
    barrier = Async::Barrier.new
    results = {}

    # Fibers are cooperative - regular Hash is safe
    tool_calls.each do |tool_call|
      barrier.async do
        result = if semaphore
          semaphore.acquire { execute.call(tool_call) }
        else
          execute.call(tool_call)
        end
        results[tool_call.id] = result
      rescue => error  # Catches StandardError, NOT Async::Stop (cancellation propagates)
        # Store error as result so LLM sees it
        results[tool_call.id] = "Error: #{error.class}: #{error.message}"
        warn "[RubyLLM] Tool #{tool_call.id} failed: #{error.message}"
      end
    end

    # Wait for ALL tasks to complete (barrier ensures no orphans)
    # Required - blocks until all complete, handles empty case gracefully
    barrier.wait

    results
  end
end
```

**Characteristics:**
- Lightweight (no OS thread overhead)
- Cooperative scheduling (no race conditions within fibers)
- `Async::Barrier` ensures all tasks complete even if some fail
- `Sync {}` is idiomatic - reuses existing event loop if available, creates one if needed
- Errors stored in results (LLM sees failure message)
- `Async::Stop` propagates through (not caught by `rescue => error`)
- Great for I/O-bound operations (API calls, database queries)
- Requires `async` gem (optional dependency)

**Why `Sync {}` instead of `Async {}.wait`?**
- More idiomatic Async pattern
- Automatically reuses existing event loop if called from Async context
- Creates minimal event loop if called from non-Async context
- Slightly more efficient (no extra Task wrapper)
- Handles nested calls correctly

#### Thread Executor (Native Threads)

Uses Ruby's native threads with stdlib `Mutex` for synchronization. No external gems required.

```ruby
RubyLLM.register_tool_executor(:threads) do |tool_calls, max_concurrency:, &execute|
  results = {}
  mutex = Mutex.new
  semaphore = max_concurrency ? Thread::SizedQueue.new(max_concurrency) : nil

  # Fill semaphore with permits
  max_concurrency&.times { semaphore << :permit }

  threads = tool_calls.map do |tool_call|
    Thread.new do
      # Acquire permit (blocks if none available)
      permit = semaphore&.pop

      begin
        result = execute.call(tool_call)
        mutex.synchronize { results[tool_call.id] = result }
      rescue => error
        # Store error as result so LLM sees it
        error_result = "Error: #{error.class}: #{error.message}"
        mutex.synchronize { results[tool_call.id] = error_result }
        warn "[RubyLLM] Tool #{tool_call.id} failed: #{error.message}"
      ensure
        # Release permit
        semaphore&.push(permit) if permit
      end
    end
  end

  threads.each(&:join)
  results
end
```

**Characteristics:**
- True parallelism (for JRuby/TruffleRuby)
- Works with any Ruby implementation
- No external dependencies (stdlib only)
- All threads complete even if some fail
- Errors stored in results (LLM sees failure message)
- Good for CPU-bound operations
- Higher overhead than fibers

### Choosing an Executor

| Executor | Best For | Dependencies | Overhead |
|----------|----------|--------------|----------|
| `:async` | I/O-bound tools (API calls) | `async` gem | Low (fibers) |
| `:threads` | CPU-bound tools, broad compatibility | None (stdlib) | Higher (threads) |

```ruby
# I/O-bound: Use async (lighter weight)
chat = RubyLLM.chat(tool_concurrency: :async, max_concurrency: 10)

# CPU-bound or no async gem: Use threads
chat = RubyLLM.chat(tool_concurrency: :threads, max_concurrency: 4)
```

### Custom Executors

Users can register their own executors:

```ruby
# Actor-based executor (if using Celluloid, Ractor, etc.)
RubyLLM.register_tool_executor(:actors) do |tool_calls, max_concurrency:, &execute|
  # Custom implementation
  results = {}
  # ... actor-based execution ...
  results
end

# Process-based executor (for true parallelism in MRI)
RubyLLM.register_tool_executor(:processes) do |tool_calls, max_concurrency:, &execute|
  require 'parallel'
  results = {}
  Parallel.each(tool_calls, in_processes: max_concurrency) do |tool_call|
    results[tool_call.id] = execute.call(tool_call)
  end
  results
end
```

## Hook Use Cases

### 1. Rate Limiting

```ruby
class RateLimitedChat < RubyLLM::Chat
  def initialize(**)
    super
    @rate_limiter = Async::Semaphore.new(10)  # Max 10 concurrent
  end

  def around_tool_execution(tool_call, tool_instance:)
    @rate_limiter.acquire { super }
  end
end
```

### 2. Caching

```ruby
class CachedChat < RubyLLM::Chat
  def initialize(**)
    super
    @cache = {}
  end

  def around_tool_execution(tool_call, tool_instance:)
    cache_key = [tool_call.name, tool_call.arguments].hash
    @cache.fetch(cache_key) { yield }
  end
end
```

### 3. Circuit Breaker

```ruby
class ResilientChat < RubyLLM::Chat
  def around_tool_execution(tool_call, tool_instance:)
    if @circuit_breaker.open?(tool_call.name)
      { error: "Service unavailable" }
    else
      yield
    end
  end
end
```

### 4. Instrumentation

```ruby
class InstrumentedChat < RubyLLM::Chat
  def around_tool_execution(tool_call, tool_instance:)
    start_time = Time.now
    result = yield
    duration = Time.now - start_time

    @metrics.record(tool_call.name, duration)
    result
  end
end
```

### 5. Dry-Run Mode

```ruby
class TestableChat < RubyLLM::Chat
  def around_tool_execution(tool_call, tool_instance:)
    if @dry_run
      { simulated: true, would_call: tool_call.name, args: tool_call.arguments }
    else
      yield
    end
  end
end
```

### 6. Layered Resource Management

```ruby
class ProductionChat < RubyLLM::Chat
  def initialize(**)
    super
    @global_limiter = GlobalRateLimiter.instance
    @local_limiter = Async::Semaphore.new(5)
    @metrics = Metrics.new
  end

  def around_tool_execution(tool_call, tool_instance:)
    # Layer 1: Global rate limit
    @global_limiter.acquire do
      # Layer 2: Local rate limit
      @local_limiter.acquire do
        # Layer 3: Instrumentation
        start_time = Time.now
        result = super
        @metrics.record(tool_call.name, Time.now - start_time)
        result
      end
    end
  end
end
```

## Real-World Usage Patterns

### Pattern 1: High-Throughput API Client

```ruby
# Weather service with rate limits
chat = RubyLLM.chat(
  tool_concurrency: :async,
  max_concurrency: 10  # API allows 10 concurrent requests
).with_tools(WeatherAPI, ForecastAPI, AlertsAPI)

# Process many cities efficiently
chat.ask("Get weather for NYC, LA, Chicago, Miami, Seattle, Denver")
```

### Pattern 2: Resource-Constrained Environment

```ruby
# Limited memory/connections
chat = RubyLLM.chat(
  tool_concurrency: :async,
  max_concurrency: 2  # Conservative limit
).with_tools(DatabaseQuery, CacheCheck, ExternalAPI)
```

### Pattern 3: Progressive Enhancement

```ruby
# Start sequential, enable concurrency after testing
chat = RubyLLM.chat.with_tools(MyTools)
chat.ask("Test query")  # Sequential

# Enable concurrency after validation
chat.with_tool_concurrency(:async, max: 5)
chat.ask("Production query")  # Concurrent
```

### Pattern 4: Debug Mode

```ruby
# Force sequential for debugging
if ENV['DEBUG']
  chat.with_tool_concurrency(nil)  # Disable concurrency
end
```

## Cancellation and Interruption Handling

### Async Executor (Fiber Cancellation)

**Async automatically propagates cancellation** - when parent task is stopped, all child tasks are stopped:

```ruby
Async do |parent_task|
  chat = RubyLLM.chat(tool_concurrency: :async)

  # Start concurrent tool execution
  result = chat.ask("Process data")

  # If parent_task.stop is called, all child fibers are cancelled
end
```

**What happens:**
- Parent task stop propagates to all child tasks via `Async::Stop` exception
- `Async::Barrier.wait` is interrupted
- All fibers clean up via their `ensure` blocks
- No zombie fibers
- HTTP connections closed by Faraday/Net::HTTP

**No explicit cleanup needed** - Async's task hierarchy handles everything.

### Thread Executor (Thread Cancellation)

**Threads do NOT automatically cancel** - they continue running even if the calling fiber is stopped. However, we can implement **cooperative cancellation**:

```ruby
Async do |parent_task|
  chat = RubyLLM.chat(tool_concurrency: :threads)

  result = chat.ask("Process data")
  # If parent_task.stop is called, cancellation is propagated via flag
end
```

**Cooperative Cancellation Pattern:**

```ruby
# Exception for forced cancellation - inherits from Exception to avoid being caught
class CancellationInterrupt < Exception; end

RubyLLM.register_tool_executor(:threads) do |tool_calls, max_concurrency:, &execute|
  results = {}
  mutex = Mutex.new
  completion_queue = Thread::Queue.new
  semaphore = max_concurrency ? Thread::SizedQueue.new(max_concurrency) : nil

  max_concurrency&.times { semaphore << :permit }

  threads = tool_calls.map do |tool_call|
    Thread.new do
      permit = semaphore&.pop
      begin
        result = execute.call(tool_call)
        mutex.synchronize { results[tool_call.id] = result }
      rescue CancellationInterrupt
        # Clean exit on cancellation
        mutex.synchronize { results[tool_call.id] = "Cancelled" }
      rescue => error
        error_result = "Error: #{error.class}: #{error.message}"
        mutex.synchronize { results[tool_call.id] = error_result }
        warn "[RubyLLM] Tool #{tool_call.id} failed: #{error.message}"
      ensure
        semaphore&.push(permit) if permit
        completion_queue.push(:done)  # Signal completion
      end
    end
  end

  begin
    # Wait for all threads using fiber-scheduler-aware primitive
    tool_calls.size.times { completion_queue.pop }
  rescue Exception => e
    # Parent was cancelled (Async::Stop or other exception)

    # Inject cancellation into running threads - interrupts blocked I/O immediately
    threads.each do |thread|
      thread.raise(CancellationInterrupt, "Parent cancelled") if thread.alive?
    end

    # Wait for threads to clean up (with timeout)
    threads.each { |t| t.join(5) }

    # Force kill any stuck threads (last resort)
    threads.each { |t| t.kill if t.alive? }

    raise  # Re-raise original exception
  end

  threads.each(&:join)
  results
end
```

**How it works:**

1. **Main fiber waits on Queue**: The executor fiber calls `completion_queue.pop` which is fiber-scheduler-aware
2. **Parent cancellation**: When parent fiber gets `Async::Stop`, the `pop` is interrupted and raises exception
3. **Exception handler runs**: The `rescue Exception` block runs IN THE MAIN FIBER (not in worker threads)
4. **Thread.raise from outside**: The main fiber calls `thread.raise(CancellationInterrupt)` on each worker thread FROM OUTSIDE
5. **Immediate interruption**: Even if a worker thread is blocked on `socket.read`, the exception is injected immediately
6. **CancellationInterrupt < Exception**: Using Exception (not StandardError) ensures it's not accidentally caught by `rescue => e`
7. **Graceful cleanup**: Wait for threads to finish, force kill as last resort

**Visual timeline:**
```
Main Fiber (Executor)          Worker Thread 1              Worker Thread 2
─────────────────────          ───────────────              ───────────────
starts worker threads
calls completion_queue.pop     executes tool                executes tool
  (blocked, waiting)           (blocked on HTTP)            (blocked on HTTP)

Parent fiber cancelled!
  ↓
Async::Stop raised
  ↓
rescue Exception caught
  ↓
thread.raise(Cancel) ────────→ CancellationInterrupt!
                               socket.read interrupted
                               exception propagates
                               ensure block runs
                               connection closed
thread.raise(Cancel) ─────────────────────────────────────→ CancellationInterrupt!
                                                            socket.read interrupted
                                                            exception propagates
                                                            ensure block runs
                                                            connection closed
threads.join(5)                exits cleanly                exits cleanly
  ↓
re-raises Async::Stop
```

**Key insight**: The cancellation is triggered by the MAIN FIBER (the one running the executor), which calls `Thread.raise` on worker threads from OUTSIDE. The workers don't need to poll or check anything - the exception is forcibly injected into them.

**Critical Insight: Thread.raise Interrupts Blocking Operations**

| Blocking Operation | Interrupted? | Notes |
|-------------------|--------------|-------|
| `sleep(n)` | ✅ Immediate | Timer-based, always works |
| `socket.read` (Net::HTTP) | ✅ Immediate | I/O wait is interruptible |
| `Mutex#synchronize` | ✅ Immediate | Condition wait is interruptible |
| `Queue#pop` | ✅ Immediate | Thread sleep is interruptible |
| `IO.select` | ✅ Immediate | Select syscall is interruptible |
| Ruby CPU work | ✅ Soon | At next interrupt check point |
| Good C extension | ✅ Immediate | Uses `rb_nogvl()` properly |
| Bad C extension | ⚠️ Delayed | Waits until C code returns |

**So even if a thread is blocked waiting for a 60-second HTTP response, `Thread.raise` will interrupt it immediately!**

The exception propagates through the call stack, closing connections properly (Faraday/Net::HTTP handle exceptions in their cleanup).

**Force kill as last resort**: `Thread.kill` is dangerous because it can leave mutexes locked or files open. Only use after timeout if thread is truly stuck (rare with well-written code).

### Thread.kill on Async Executor (DANGEROUS) ⚠️

**What if the Async executor is running inside a Thread, and you kill that Thread?**

All fibers stop immediately, but **it's brutal and dangerous**:

```ruby
worker_thread = Thread.new do
  Async do |task|
    barrier = Async::Barrier.new

    tool_calls.each do |tool_call|
      barrier.async do
        result = execute_tool(tool_call)  # Long-running HTTP request
        # File handles open, connections active
        results[tool_call.id] = result
      ensure
        # THIS MAY NEVER RUN!
        close_connections
      end
    end

    barrier.wait
  end
end

# Later, in main thread:
worker_thread.kill  # DANGER! All fibers die immediately
```

**What happens:**

| Aspect | Result |
|--------|--------|
| Current fiber's ensure blocks | ✅ Run (exception propagates normally) |
| Suspended fibers' ensure blocks | ❌ NEVER RUN - they're abandoned |
| Async reactor cleanup | ⚠️ Attempted but may fail |
| File handles | ❌ May leak |
| Network connections | ❌ May leak |
| Mutex locks | ❌ May stay locked |

**Why this is so dangerous:**

```
Thread.kill → Exception raised in current execution context
                    ↓
            Only CURRENT fiber handles it
                    ↓
            Suspended fibers are ABANDONED
                    ↓
            Their ensure blocks NEVER run
                    ↓
            Resources leaked
```

When a thread is killed, only the **currently executing fiber** receives the exception. Other fibers that are suspended (waiting for I/O, sleeping, etc.) never get a chance to clean up.

**Async tries to help:**

```ruby
# In Reactor#close:
def close
  self.run_loop do
    until self.terminate     # Try to stop all tasks
      self.run_once!         # Resume fibers to let them cleanup
    end
  end
end
```

But this cleanup loop can fail if:
- An exception is already propagating
- The event loop is in inconsistent state
- Resources are corrupted

**NEVER use Thread.kill with Async** - use cooperative cancellation instead:

```ruby
class SafeAsyncThreadExecutor
  def initialize
    @shutdown_signal = Thread::Queue.new
    @worker_thread = nil
  end

  def execute(tool_calls, &block)
    results = {}
    mutex = Mutex.new

    @worker_thread = Thread.new do
      Async do |task|
        # Shutdown watcher (runs inside event loop)
        watcher = task.async(transient: true) do
          @shutdown_signal.pop  # Blocks until cancelled
          task.stop  # Gracefully stop everything
        end

        # Actual work
        barrier = Async::Barrier.new
        tool_calls.each do |tc|
          barrier.async do
            result = block.call(tc)
            mutex.synchronize { results[tc.id] = result }
          ensure
            # This WILL run on cancellation
            cleanup_resources
          end
        end

        barrier.wait
      ensure
        watcher.stop rescue nil
      end
    end

    @worker_thread.join
    results
  end

  def cancel
    return unless @worker_thread&.alive?

    # Step 1: Signal graceful shutdown
    @shutdown_signal.push(:cancel)

    # Step 2: Wait for graceful shutdown (with timeout)
    if @worker_thread.join(5)
      puts "Shutdown completed gracefully"
    else
      # Step 3: Force kill (LAST RESORT - resources will leak!)
      warn "Graceful shutdown failed, forcing termination"
      @worker_thread.kill
      @worker_thread.join(1)
    end
  end
end
```

**This pattern:**
- Uses Async's native `task.stop` for proper cleanup
- Watcher fiber runs inside the event loop
- All ensure blocks have a chance to run
- Only falls back to Thread.kill if absolutely necessary
- Accepts that forced termination WILL leak resources

**Best practices:**
1. **DON'T run Async inside a Thread you might kill**
2. **Use cooperative cancellation** - signal shutdown via queue/flag
3. **Keep Async in main thread** with proper task management
4. **OR use pure threads** for cancellable operations
5. **Accept resource leaks** if you must Thread.kill (rare cases)

**Summary:**
- Thread.kill on Async = suspended fibers are orphaned with no cleanup
- Use cooperative cancellation pattern for safe termination
- Only Thread.kill as absolute last resort (accept resource leaks)

### CRITICAL: Chat State Consistency ⚠️

**The most important concern**: Partial tool results leave Chat in an INVALID state.

```ruby
# Scenario: 3 tools requested, interrupted after 2 complete
@messages = [
  user: "Get weather, stock, and news",
  assistant: { tool_calls: [A, B, C] },  # Requested 3 tools
  tool: result_A,  # Only 2 results added before interruption
  tool: result_B,
  # MISSING: result_C
]
```

**LLM APIs REJECT incomplete tool results:**
- OpenAI: "Tool call C was not responded to"
- Anthropic: "All tool_use blocks must have corresponding tool_result"

This means the Chat cannot continue the conversation.

### Solution: Atomic Message Addition

To ensure consistency, add ALL tool result messages atomically AFTER all tools complete:

```ruby
def execute_tools_concurrently(tool_calls)
  # Phase 1: Execute all tools concurrently (fire events as they complete)
  results = parallel_execute_tools(tool_calls)

  # Phase 2: Add messages atomically (all-or-nothing)
  add_tool_results_atomically(tool_calls, results)

  find_halt_result(tool_calls, results)
end

def add_tool_results_atomically(tool_calls, results)
  messages = []

  @messages_mutex.synchronize do
    tool_calls.each_key do |id|
      tool_call = tool_calls[id]
      result = results[id]

      tool_payload = result.is_a?(Tool::Halt) ? result.content : result
      content = content_like?(tool_payload) ? tool_payload : tool_payload.to_s
      message = Message.new(role: :tool, content:, tool_call_id: tool_call.id)
      @messages << message
      messages << message
    end
  end

  # Fire events OUTSIDE mutex (better performance)
  messages.each { |msg| emit(:end_message, msg) }
end
```

**Trade-off**: This means `end_message` events fire after ALL tools complete, not immediately as each finishes. However:
- `tool_call` and `tool_result` events still fire immediately (for progress monitoring)
- Chat state is always valid
- No partial results that break API calls
- Events fire outside mutex (slow callbacks don't block other operations)

### Hybrid Approach (Recommended)

Fire `tool_call` and `tool_result` events immediately, but defer message addition:

```ruby
def execute_single_tool_with_events(tool_call)
  emit(:new_message)
  emit(:tool_call, tool_call)

  tool_instance = tools[tool_call.name.to_sym]
  result = around_tool_execution(tool_call, tool_instance:) do
    tool_instance.call(tool_call.arguments)
  end

  emit(:tool_result, result)
  result  # Don't add message yet
end

def execute_tools_concurrently(tool_calls)
  # Phase 1: Execute with events (immediate feedback)
  results = parallel_execute_tools(tool_calls) do |tool_call|
    execute_single_tool_with_events(tool_call)
  end

  # Phase 2: Add messages atomically (state consistency)
  add_tool_results_atomically(tool_calls, results)

  find_halt_result(tool_calls, results)
end

def add_tool_results_atomically(tool_calls, results)
  messages = []

  @messages_mutex.synchronize do
    tool_calls.each_key do |id|
      tool_call = tool_calls[id]
      result = results[id]

      tool_payload = result.is_a?(Tool::Halt) ? result.content : result
      content = content_like?(tool_payload) ? tool_payload : tool_payload.to_s
      message = Message.new(role: :tool, content:, tool_call_id: tool_call.id)
      @messages << message
      messages << message
    end
  end

  # Fire events OUTSIDE mutex (better performance, no blocking)
  messages.each { |msg| emit(:end_message, msg) }
end
```

This provides:
- ✅ Immediate progress feedback via `tool_call`/`tool_result` events
- ✅ Consistent Chat state (all messages added together)
- ✅ Safe for cancellation (no partial results)
- ✅ Valid for LLM API calls
- ✅ Events fire outside mutex (slow callbacks don't block)

### Diagnostic Methods

Provide methods for users to check/repair consistency:

```ruby
class Chat
  # Check if all tool calls have corresponding results
  def tool_results_complete?
    return true unless last_message_has_tool_calls?

    expected_ids = last_tool_call_ids
    actual_ids = pending_tool_result_ids

    expected_ids == actual_ids
  end

  # Remove incomplete tool call if interrupted
  def repair_incomplete_tool_calls!
    return self if tool_results_complete?

    @messages_mutex.synchronize do
      # Remove partial tool results
      @messages.pop while @messages.last&.role == :tool
      # Remove the incomplete assistant message
      @messages.pop if @messages.last&.tool_call?
    end
    self
  end
end
```

## Thread-Safety Requirements

**IMPORTANT**: When using concurrent tool execution, users must ensure thread safety.

### Tool Instances Must Be Thread-Safe

```ruby
# SAFE: No mutable instance state
class ThreadSafeTool < RubyLLM::Tool
  def execute(query:)
    ExternalAPI.call(query)  # Each call is independent
  end
end

# NOT SAFE: Shared mutable state
class UnsafeTool < RubyLLM::Tool
  def initialize
    @cache = {}  # Shared across concurrent calls!
  end

  def execute(key:)
    @cache[key] ||= expensive_call(key)  # Race condition!
  end
end

# SAFE: Thread-safe cache
class SafeCachedTool < RubyLLM::Tool
  def initialize
    @cache = {}
    @mutex = Mutex.new
  end

  def execute(key:)
    @mutex.synchronize do
      @cache[key] ||= expensive_call(key)
    end
  end
end
```

### Cancellation-Aware Tools (Optional Enhancement)

For better cancellation responsiveness, tools can check for cancellation periodically:

```ruby
class RubyLLM::Tool
  class CancellationError < StandardError; end

  # Set by executor before each call
  attr_accessor :cancellation_token

  def call(args)
    check_cancelled!
    RubyLLM.logger.debug "Tool #{name} called with: #{args.inspect}"
    result = execute(**args.transform_keys(&:to_sym))
    check_cancelled!
    RubyLLM.logger.debug "Tool #{name} returned: #{result.inspect}"
    result
  end

  protected

  def check_cancelled!
    return unless @cancellation_token&.cancelled?
    raise CancellationError, @cancellation_token.reason || "Cancelled"
  end

  # Alias for ergonomic usage in tools
  alias_method :yield_if_cancelled, :check_cancelled!
end

# Cancellation token (passed by executor)
class CancellationToken
  def initialize
    @cancelled = false
    @reason = nil
    @mutex = Mutex.new
  end

  def cancel!(reason = "Cancelled")
    @mutex.synchronize do
      @cancelled = true
      @reason = reason
    end
  end

  def cancelled?
    @mutex.synchronize { @cancelled }
  end

  def reason
    @mutex.synchronize { @reason }
  end
end
```

**Tool implementation patterns:**

```ruby
# Pattern 1: Check between iterations (recommended)
class PaginatedAPITool < RubyLLM::Tool
  def execute(query:)
    results = []
    page = 1

    loop do
      yield_if_cancelled  # Check before each API call

      response = api.search(query, page: page)
      break if response.empty?

      results.concat(response.items)
      page += 1
    end

    results
  end
end

# Pattern 2: Cancellation-aware timeout for long HTTP requests
class LongHTTPTool < RubyLLM::Tool
  def execute(url:)
    # Check cancellation every second during long request
    with_periodic_cancellation_check(30) do
      Net::HTTP.get(URI(url))
    end
  end

  private

  def with_periodic_cancellation_check(total_seconds)
    deadline = Time.now + total_seconds

    loop do
      remaining = deadline - Time.now
      raise Timeout::Error, "Request timed out" if remaining <= 0

      begin
        # Try for 1 second at a time
        return Timeout.timeout([remaining, 1.0].min) { yield }
      rescue Timeout::Error
        yield_if_cancelled  # Check cancellation every second
        retry
      end
    end
  end
end

# Pattern 3: Simple tool (automatic checks in Tool#call)
class SimpleTool < RubyLLM::Tool
  def execute(query:)
    # Automatic pre/post check via Tool#call wrapper
    external_api.fetch(query)
  end
end
```

**Benefits:**
- Tools can respond to cancellation faster than waiting for completion
- Long-running operations (pagination, bulk processing) become interruptible
- Faraday requests can be broken into shorter timeouts with periodic checks

**Note**: This is an optional enhancement. Tools that don't use `yield_if_cancelled` still work - they just won't respond to cancellation until the current operation completes.

### Callbacks Must Be Thread-Safe

```ruby
# SAFE: No shared state
chat.on_tool_call { |tc| logger.info(tc.name) }

# NOT SAFE: Shared mutable state without synchronization
results = []
chat.on_tool_call { |tc| results << tc.name }  # Race condition!

# SAFE: Synchronized access
results = []
mutex = Mutex.new
chat.on_tool_call { |tc| mutex.synchronize { results << tc.name } }

# SAFE: Use atomic operations or thread-safe collections
require 'concurrent'
counter = Concurrent::AtomicFixnum.new(0)
chat.on_tool_call { |_| counter.increment }
```

### Message Ordering

Tool result messages are added in **completion order**, not request order:

```
Request: [tool_A, tool_B, tool_C]
Completion: [tool_C (100ms), tool_A (200ms), tool_B (500ms)]
Messages: [tool_C result, tool_A result, tool_B result]
```

**This is fine** because LLM APIs match results by `tool_call_id`, not position. However:
- Debuggability may be affected (messages don't reflect request order)
- If you need ordered results, process by request order after all complete

### Halt Behavior

When multiple tools execute concurrently:
- **All tools execute** even if one returns `Tool::Halt`
- First halt by **request order** (not completion order) is returned
- Multiple halts is undefined behavior (avoid in tool design)

## Error Handling

### Tool Execution Errors

Errors in tool execution are captured and stored as results:

```ruby
# Tool raises exception
class FailingTool < RubyLLM::Tool
  def execute(...)
    raise "Connection failed"
  end
end

# Result stored as error message (LLM sees it):
# "Error: RuntimeError: Connection failed"
```

**Benefits:**
- Other tools continue executing
- LLM sees failure and can respond appropriately
- No orphaned tasks or threads

### Hook Errors

Hook errors propagate (fail fast):
```ruby
def around_tool_execution(tool_call, tool_instance:)
  @semaphore.acquire
  yield
rescue => e
  # Log infrastructure error, re-raise
  logger.error("Hook failed: #{e.message}")
  raise
ensure
  @semaphore.release rescue nil  # Always cleanup
end
```

**Contract:**
- Hook must be exception-safe (use ensure for cleanup)
- Hook errors are infrastructure failures, should propagate
- Tool execution errors are handled by the executor (stored as error result)

## Benefits

### For RubyLLM
- ✅ Clean API (`tool_concurrency` vs confusing tool-level config)
- ✅ Minimal changes (~100 lines)
- ✅ Backwards compatible (default is sequential)
- ✅ Extensible (registry pattern)
- ✅ Ruby-idiomatic (`around_*` pattern matches Rails conventions)

### For Users
- ✅ **Performance**: 3-10x faster for multi-tool calls
- ✅ **Rate limiting**: Prevent API quota exhaustion
- ✅ **Customization**: Hook provides infinite flexibility
- ✅ **Observability**: Track tool execution in real-time
- ✅ **Resilience**: Circuit breakers, retries, caching

### For Library Authors
- ✅ Clean composition with `super`
- ✅ No method overriding required
- ✅ Layered resource management
- ✅ Can short-circuit execution (caching, mocks)

## Implementation Checklist

**PREREQUISITE**: Implement MULTI_SUBSCRIBER_CALLBACKS.md first! This plan depends on:
- `emit()` method existing (from multi-subscriber system)
- `@callback_monitor` being initialized
- Monitor gem being required

The combined `initialize` should look like:
```ruby
def initialize(...)
  # Messages (this plan)
  @messages = []
  @messages_mutex = Mutex.new

  # Callbacks (MULTI_SUBSCRIBER_CALLBACKS.md)
  @callbacks = { new_message: [], end_message: [], tool_call: [], tool_result: [] }
  @callback_monitor = Monitor.new

  # Concurrency (this plan)
  @tool_concurrency = tool_concurrency
  @max_concurrency = max_concurrency
end
```

### Phase 1: Core Concurrency
- [ ] Ensure `require 'monitor'` is in Chat (from MULTI_SUBSCRIBER_CALLBACKS.md)
- [ ] Add `tool_concurrency` and `max_concurrency` to `Chat#initialize`
- [ ] Add `@messages_mutex = Mutex.new` for thread-safe message addition
- [ ] Add `with_tool_concurrency` chainable method
- [ ] Implement `concurrent_tools?` check
- [ ] **CRITICAL**: Fix `add_message` to use `@messages` directly (not getter)
- [ ] Make `add_message` thread-safe with mutex synchronization
- [ ] Add YARD comments on `messages` getter warning about direct mutation
- [ ] Add `message_history` method (thread-safe frozen snapshot)
- [ ] Add `set_messages(new_messages)` method (thread-safe replacement)
- [ ] Add `snapshot_messages` method (thread-safe checkpoint)
- [ ] Add `restore_messages(snapshot)` method (restore from checkpoint)
- [ ] Update `reset_messages!` to use mutex
- [ ] Add `execute_tools_sequentially` (refactor existing)
- [ ] Add `execute_tools_concurrently` (hybrid pattern)
- [ ] Add `execute_single_tool_with_message` method (sequential: fires all events + adds message)
- [ ] Add `execute_single_tool_with_events` method (concurrent: fires events only)
- [ ] Add `execute_single_tool` shared method (core execution + tool_call event)
- [ ] Add `add_tool_result_message` helper
- [ ] Add `add_tool_results_atomically` method (atomic batch addition)
- [ ] Add `tool_results_complete?` diagnostic method
- [ ] Add `repair_incomplete_tool_calls!` recovery method

### Phase 1.5: Message Transaction Support (Critical)
- [ ] Add `with_message_transaction` method (index-based rollback, O(1) memory)
- [ ] Refactor `complete()` to call `execute_tool_call_sequence()`
- [ ] Add `execute_tool_call_sequence()` wrapping tool execution in transaction
- [ ] Ensure assistant message + tool results are atomic (all or nothing)
- [ ] Use `@messages.slice!(start_index..-1)` for efficient rollback
- [ ] Test cancellation properly rolls back incomplete state
- [ ] Test exception handling rolls back incomplete state
- [ ] Ensure nested transactions work (each uses local start_index variable)

### Phase 2: Extensibility Hook
- [ ] Add `around_tool_execution` default implementation
- [ ] Call hook in `execute_single_tool`
- [ ] Document hook contract (exception safety, return values)

### Phase 3: Executor Registry
- [ ] Add `RubyLLM.tool_executors` hash
- [ ] Add `RubyLLM.register_tool_executor` method
- [ ] Implement `:async` executor (fibers, Async::Barrier for error handling)
- [ ] Implement `:threads` executor (stdlib Mutex + Thread, error capture)
- [ ] Add cooperative cancellation to thread executor (Thread::Queue + Thread.raise)
- [ ] Add CancellationToken class for cancellation state
- [ ] Add CancellationError exception class
- [ ] Auto-register both executors on load
- [ ] Raise clear error if :async requested but async gem not installed
- [ ] Ensure errors are stored as results (not re-raised)
- [ ] Ensure all tasks complete even if some fail

### Phase 3.5: Cancellation-Aware Tools (Optional)
- [ ] Add `cancellation_token` attr_accessor to Tool class
- [ ] Add `check_cancelled!` protected method to Tool
- [ ] Add `yield_if_cancelled` alias for ergonomic usage
- [ ] Wrap Tool#call with pre/post cancellation checks
- [ ] Document cancellation patterns for tool authors
- [ ] Add periodic cancellation check helper for long operations

### Phase 4: Testing
- [ ] Unit tests for sequential execution (no regression)
- [ ] Unit tests for concurrent execution (hybrid pattern)
- [ ] Unit tests for hook behavior
- [ ] Integration tests with real tools
- [ ] Thread/Fiber safety tests
- [ ] Error handling tests (errors stored as results)
- [ ] Halt behavior tests (first halt by request order)
- [ ] Message ordering tests (request order via atomic addition)
- [ ] Async::Barrier tests (all tasks complete even with failures)
- [ ] Thread-safe message addition tests
- [ ] Atomic message addition tests (all-or-nothing semantics)
- [ ] Chat state consistency tests (no partial tool results)
- [ ] Cancellation tests (Async executor stops cleanly)
- [ ] Cancellation tests (Thread executor cooperative cancellation)
- [ ] Thread::Queue fiber-scheduler awareness tests
- [ ] Thread.raise injection tests (CancellationError propagation)
- [ ] CancellationToken tests (thread-safe flag management)
- [ ] Cancellation-aware tool tests (yield_if_cancelled patterns)
- [ ] Diagnostic method tests (tool_results_complete?, repair_incomplete_tool_calls!)
- [ ] Message transaction tests (index-based rollback)
- [ ] Transaction rollback on exception tests
- [ ] Transaction rollback on cancellation tests
- [ ] Nested transaction tests (each uses local start_index)
- [ ] Chat state valid after rollback tests (no orphaned tool_calls)
- [ ] Verify `@messages.slice!` is O(1) for end truncation

### Phase 5: Documentation
- [ ] Update README with new API
- [ ] Add guide for concurrent tool execution
- [ ] Document hook patterns (caching, rate limiting, etc.)
- [ ] Document thread-safety requirements for tools and callbacks
- [ ] Document error handling behavior (errors stored as results)
- [ ] Document hybrid pattern (events fire immediately, messages added atomically)
- [ ] Document halt behavior (all tools execute, first halt by request order)
- [ ] Document cancellation behavior (Async automatic, threads cooperative)
- [ ] Document cooperative cancellation for thread executor
- [ ] Document cancellation-aware tool patterns (yield_if_cancelled, periodic checks)
- [ ] Document Chat state consistency (atomic message addition)
- [ ] Document diagnostic methods (tool_results_complete?, repair_incomplete_tool_calls!)
- [ ] Document message transaction support (index-based rollback, O(1) memory)
- [ ] Document cancellation rollback behavior (assistant message + tools atomic)
- [ ] Document message management API (message_history, set_messages, snapshot_messages)
- [ ] Document thread-safe vs backwards-compatible access patterns
- [ ] Migration guide from original proposal

## Files Changed

1. `lib/ruby_llm.rb` - Add `chat` factory changes, executor registry
2. `lib/ruby_llm/chat.rb` - Core implementation (~100 lines)
3. `lib/ruby_llm/tool_executor.rb` - Executor registry and built-in implementations
4. `spec/chat_concurrency_spec.rb` - Tests for concurrent execution
5. `spec/tool_executor_spec.rb` - Tests for both async and thread executors

## Breaking Changes

**None.** Default behavior is sequential, existing code works unchanged.

## Summary

This design provides:
1. **Clean semantics** - Execution strategy is a chat property
2. **Maximum flexibility** - Hook allows any customization
3. **Immediate feedback** - `tool_call`/`tool_result` events fire as tools complete
4. **State consistency** - Atomic message addition ensures valid Chat state
5. **Cancellation safety** - Async automatic propagation, threads cooperative cancellation
6. **Cancellation awareness** - Optional tool patterns for responsive interruption
7. **Transaction support** - Rollback on failure keeps Chat state valid
8. **Thread safety** - Mutex protects shared state, hybrid pattern
9. **Ruby conventions** - Matches Rails' `around_action` pattern
10. **Minimal surface area** - One new method, few parameters

The hybrid pattern balances immediate event feedback with Chat state consistency. Cooperative cancellation for the thread executor uses fiber-scheduler-aware primitives (`Thread::Queue`) and `Thread.raise` for exception injection, while tools can optionally use `yield_if_cancelled` for faster response. The `around_tool_execution` hook is the key enabler for sophisticated resource management without method overriding.

## Expert Verification ✅

This plan has been reviewed and validated by:

### RubyLLM Expert Review
- ✅ **Integration verified**: Works seamlessly with multi-subscriber callbacks
- ✅ **Hybrid pattern approved**: Optimal balance of feedback and consistency
- ✅ **State management correct**: Atomic message addition prevents invalid Chat state
- ✅ **Hook design sound**: `around_tool_execution` integrates cleanly with callbacks
- ⚠️ **ActiveRecord fix required**: See MULTI_SUBSCRIBER_CALLBACKS.md for details
- ⚠️ **CRITICAL BUG**: `add_message` uses `messages <<` (getter), must change to `@messages <<`
- ✅ **Message API designed**: `message_history`, `set_messages`, `snapshot_messages` added
- ✅ **Backwards compatible**: `chat.messages` still returns live array (direct mutation at user's risk)

### Async Expert Review
- ✅ **Sync {} usage verified**: More idiomatic than `Async {}.wait`
- ✅ **Barrier + Semaphore pattern correct**: Proper concurrency control
- ✅ **Error handling validated**: `rescue => error` doesn't catch `Async::Stop`
- ✅ **Monitor/Mutex safe**: Both cooperate with fiber scheduler
- ✅ **Thread::Queue fiber-aware**: Proper cancellation propagation

**Key Corrections Applied:**
1. Changed `Async {}.wait` to `Sync {}` for more idiomatic usage
2. Added `require 'kernel/sync'` for Sync method
3. Fire `end_message` events OUTSIDE mutex for better performance
4. Clarified that `barrier.wait` is required (not auto-wait)
5. Simplified transaction to index-based rollback (O(1) memory, no array duplication)
6. Fixed `add_message` to use `@messages` directly (not the getter method)
7. Added thread-safe message management API (`message_history`, `set_messages`, etc.)

**Confidence Level: HIGH** - Both experts validated the design with minor corrections applied.

```ruby
# Final recommended usage
chat = RubyLLM.chat(
  model: "claude-sonnet-4",
  tool_concurrency: :async,
  max_concurrency: 5
).with_tools(Weather, Stock, Currency)

# With customization
class MyChat < RubyLLM::Chat
  def around_tool_execution(tool_call, tool_instance:)
    # Add your magic here
    super
  end
end
```
