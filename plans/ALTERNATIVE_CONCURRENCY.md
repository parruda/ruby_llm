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

### Concurrent Execution (Fire-As-Complete Pattern)

```ruby
def execute_tools_concurrently(tool_calls)
  results = parallel_execute_tools(tool_calls)

  # Check for halt after all tools complete
  halt_result = nil
  results.each_value do |result|
    halt_result = result if result.is_a?(Tool::Halt)
  end

  halt_result
end

def parallel_execute_tools(tool_calls)
  executor = RubyLLM.tool_executors[@tool_concurrency]
  raise ArgumentError, "Unknown executor: #{@tool_concurrency}" unless executor

  executor.call(tool_calls.values, max_concurrency: @max_concurrency) do |tool_call|
    execute_single_tool_with_message(tool_call)
  end
end
```

### Single Tool Execution (Shared)

```ruby
# For sequential execution - fires all events
def execute_single_tool_with_message(tool_call)
  @on[:new_message]&.call
  result = execute_single_tool(tool_call)
  message = add_tool_result_message(tool_call, result)
  @on[:end_message]&.call(message)
  result
end

# Core tool execution - fires tool_call and tool_result events
def execute_single_tool(tool_call)
  @on[:tool_call]&.call(tool_call)

  tool_instance = tools[tool_call.name.to_sym]
  result = around_tool_execution(tool_call, tool_instance:) do
    tool_instance.call(tool_call.arguments)
  end

  @on[:tool_result]&.call(result)
  result
end

def add_tool_result_message(tool_call, result)
  tool_payload = result.is_a?(Tool::Halt) ? result.content : result
  content = content_like?(tool_payload) ? tool_payload : tool_payload.to_s
  add_message(role: :tool, content:, tool_call_id: tool_call.id)
end
```

### Thread-Safe Message Addition

Since tools add messages concurrently, `add_message` must be thread-safe:

```ruby
def initialize(...)
  @messages = []
  @messages_mutex = Mutex.new
  # ...
end

def add_message(...)
  @messages_mutex.synchronize do
    # existing add_message logic
    message = Message.new(...)
    @messages << message
    message
  end
end
```

**Note**: The Mutex is only needed when `tool_concurrency` is set. For sequential execution, no synchronization overhead.

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

## Why Fire-As-Complete Pattern?

**Immediate event feedback:**
- Events fire as soon as each tool completes (not batched)
- Subscribers see real-time progress
- Better user experience (see results immediately)

**Performance where it matters:**
```
Sequential:  [Tool A: 2s] → [Tool B: 3s] → [Tool C: 1s] = 6s total
Concurrent:  [Tool A: 2s] → fires events immediately
             [Tool B: 3s] → fires events as it finishes (3s mark)
             [Tool C: 1s] → fires events immediately
             Total: 3s (3x faster!)
```

**Thread-safe by design:**
- `@messages` array protected by Mutex (only when concurrent)
- Tool results added as they complete
- Events fire immediately without blocking other tools

**Trade-offs:**
- Message order in array is non-deterministic (order tools finish, not order requested)
- Events fire concurrently (subscribers must handle concurrent calls)
- Slight synchronization overhead (Mutex for message array)

**For most use cases this is fine** - LLM APIs don't care about tool result order, and immediate feedback is more valuable than deterministic ordering.

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

Uses the `async` gem for lightweight fiber-based concurrency. Fibers are cooperative, so no race conditions occur.

```ruby
RubyLLM.register_tool_executor(:async) do |tool_calls, max_concurrency:, &execute|
  require 'async'

  Async do
    semaphore = max_concurrency ? Async::Semaphore.new(max_concurrency) : nil
    results = {}

    # Fibers are cooperative - regular Hash is safe
    tasks = tool_calls.map do |tool_call|
      Async do
        result = if semaphore
          semaphore.acquire { execute.call(tool_call) }
        else
          execute.call(tool_call)
        end
        results[tool_call.id] = result
      end
    end

    tasks.each(&:wait)
    results
  end.wait
end
```

**Characteristics:**
- Lightweight (no OS thread overhead)
- Cooperative scheduling (no race conditions)
- Great for I/O-bound operations (API calls, database queries)
- Requires `async` gem (optional dependency)

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

## Error Handling

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
- Tool execution errors are handled by the tool itself

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

### Phase 1: Core Concurrency
- [ ] Add `tool_concurrency` and `max_concurrency` to `Chat#initialize`
- [ ] Add `@messages_mutex = Mutex.new` for thread-safe message addition
- [ ] Add `with_tool_concurrency` chainable method
- [ ] Implement `concurrent_tools?` check
- [ ] Make `add_message` thread-safe with mutex synchronization
- [ ] Add `execute_tools_sequentially` (refactor existing)
- [ ] Add `execute_tools_concurrently` (fire-as-complete pattern)
- [ ] Add `execute_single_tool_with_message` method (fires all events)
- [ ] Add `execute_single_tool` shared method (fires tool_call/tool_result)
- [ ] Add `add_tool_result_message` helper

### Phase 2: Extensibility Hook
- [ ] Add `around_tool_execution` default implementation
- [ ] Call hook in `execute_single_tool`
- [ ] Document hook contract (exception safety, return values)

### Phase 3: Executor Registry
- [ ] Add `RubyLLM.tool_executors` hash
- [ ] Add `RubyLLM.register_tool_executor` method
- [ ] Implement `:async` executor (fibers, requires async gem)
- [ ] Implement `:threads` executor (stdlib Mutex + Thread, no dependencies)
- [ ] Auto-register both executors on load
- [ ] Raise clear error if :async requested but async gem not installed

### Phase 4: Testing
- [ ] Unit tests for sequential execution (no regression)
- [ ] Unit tests for concurrent execution
- [ ] Unit tests for hook behavior
- [ ] Integration tests with real tools
- [ ] Thread/Fiber safety tests
- [ ] Error handling tests

### Phase 5: Documentation
- [ ] Update README with new API
- [ ] Add guide for concurrent tool execution
- [ ] Document hook patterns (caching, rate limiting, etc.)
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
3. **Immediate feedback** - Events fire as tools complete, not batched
4. **Thread safety** - Mutex protects shared state, fire-as-complete pattern
5. **Ruby conventions** - Matches Rails' `around_action` pattern
6. **Minimal surface area** - One new method, few parameters

The `around_tool_execution` hook is the key enabler for sophisticated resource management without method overriding.

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
