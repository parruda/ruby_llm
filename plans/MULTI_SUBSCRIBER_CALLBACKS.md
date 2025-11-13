# Multi-Subscriber Callback System

## Intent

**Why this feature?**

RubyLLM's current callback system is single-subscriber: each `on_*` call replaces the previous handler. This is fundamentally limiting for real-world applications where multiple independent concerns need to observe the same events.

**Common scenarios that break:**
- **Logging + Metrics**: You want to log tool calls AND track metrics, but the second handler replaces the first
- **Plugin architecture**: Third-party plugins can't add handlers without breaking user callbacks
- **Layered applications**: Different layers (infrastructure, business logic, debugging) need independent observation
- **Testing**: Can't add test assertions without removing production callbacks

**Why multi-subscriber?**

The Observer pattern (pub/sub) is the standard solution for this problem. Multiple independent observers can react to the same event without interfering with each other. This is the pattern used by:
- ActiveSupport::Notifications (Rails)
- EventEmitter (Node.js)
- Qt Signals/Slots (C++)
- RxJS Observables (JavaScript)

**Why backwards compatible?**

Breaking existing code is unacceptable. The `on_*` methods should continue to work exactly as before (from the user's perspective), while adding multi-subscriber support. The key insight: make `on_*` methods append instead of replace internally, and return `self` for chaining compatibility.

---

## Summary

This proposal upgrades RubyLLM's single-subscriber callback system to support multiple subscribers per event while maintaining full backwards compatibility.

## Problem

Current RubyLLM callbacks are single-subscriber:

```ruby
chat.on_tool_call { |tc| puts "First handler" }
chat.on_tool_call { |tc| puts "Second handler" }  # First one is LOST!
```

This causes issues for:
- **Logging + Metrics**: Can't have both
- **Plugin systems**: Plugins override user callbacks
- **Layered architecture**: Infrastructure can't coexist with business logic
- **Testing**: Can't add assertions without removing production code

## Desired Behavior

```ruby
# Multiple subscribers - all fire
chat.on_tool_call { |tc| logger.info(tc.name) }
chat.on_tool_call { |tc| metrics.track(tc) }
chat.on_tool_call { |tc| audit_log.record(tc) }

# All three fire when tool_call event occurs
```

## API Design

### Backwards Compatible API (Simple)

```ruby
# Chainable - returns self
chat.on_tool_call { |tc| log(tc) }
    .on_tool_result { |r| track(r) }
    .with_tools(MyTool)
    .ask("Hello")

# Multiple handlers supported (behavior change, but desired)
chat.on_tool_call { |tc| handler_a(tc) }
chat.on_tool_call { |tc| handler_b(tc) }  # Both fire now!
```

### Advanced API (New)

```ruby
# Returns Subscription for unsubscribe capability
sub = chat.subscribe(:tool_call) { |tc| expensive_operation(tc) }
# ... later
sub.unsubscribe

# One-time callback (auto-unsubscribes after first fire)
chat.once(:end_message) { |msg| setup_initial_state(msg) }

# Tagged subscriptions for debugging
chat.subscribe(:tool_call, tag: "metrics") { |tc| track(tc) }
chat.callback_count(:tool_call)  # => 1
```

### Utility Methods

```ruby
# Clear all callbacks (for cleanup/testing)
chat.clear_callbacks(:tool_call)  # Clear specific event
chat.clear_callbacks               # Clear all events

# Introspection
chat.callback_count(:tool_call)  # => 3
```

## Core Implementation

**Thread-Safe Design**: Uses Ruby's stdlib `Monitor` for synchronization. Monitor is reentrant (same thread can acquire multiple times) and works correctly with both threads AND Async gem fibers (via Ruby's fiber scheduler interface).

### Subscription Class

```ruby
class Chat
  class Subscription
    attr_reader :tag

    def initialize(callback_list, callback, monitor:, tag: nil)
      @callback_list = callback_list
      @callback = callback
      @monitor = monitor  # Shared with Chat for atomic operations
      @tag = tag
      @active = true
    end

    def unsubscribe
      @monitor.synchronize do
        return false unless @active
        @callback_list.delete(@callback)
        @active = false
      end
      true
    end

    def active?
      @monitor.synchronize do
        @active && @callback_list.include?(@callback)
      end
    end

    def inspect
      "#<Subscription tag=#{@tag.inspect} active=#{active?}>"
    end
  end
end
```

### Chat Class Changes

```ruby
require 'monitor'

class Chat
  def initialize(...)
    # Change from single to multi-subscriber storage
    @callbacks = {
      new_message: [],
      end_message: [],
      tool_call: [],
      tool_result: []
    }
    @callback_monitor = Monitor.new  # Thread-safe synchronization
  end

  # Core subscription method - returns Subscription
  def subscribe(event, tag: nil, &block)
    @callback_monitor.synchronize do
      unless @callbacks.key?(event)
        raise ArgumentError, "Unknown event: #{event}. Valid events: #{@callbacks.keys.join(', ')}"
      end

      @callbacks[event] << block
      Subscription.new(@callbacks[event], block, monitor: @callback_monitor, tag: tag)
    end
  end

  # One-time subscription
  def once(event, tag: nil, &block)
    subscription = nil
    wrapper = lambda do |*args|
      subscription&.unsubscribe
      block.call(*args)
    end
    subscription = subscribe(event, tag: tag, &wrapper)
  end

  # Backwards compatible methods - return self for chaining
  def on_new_message(&block)
    subscribe(:new_message, &block)
    self
  end

  def on_end_message(&block)
    subscribe(:end_message, &block)
    self
  end

  def on_tool_call(&block)
    subscribe(:tool_call, &block)
    self
  end

  def on_tool_result(&block)
    subscribe(:tool_result, &block)
    self
  end

  # Utility methods
  def clear_callbacks(event = nil)
    @callback_monitor.synchronize do
      if event
        @callbacks[event]&.clear
      else
        @callbacks.each_value(&:clear)
      end
    end
    self
  end

  def callback_count(event = nil)
    @callback_monitor.synchronize do
      if event
        @callbacks[event]&.size || 0
      else
        @callbacks.transform_values(&:size)
      end
    end
  end

  private

  # Emit events to all subscribers - thread-safe
  def emit(event, *args)
    # Snapshot callbacks under lock (fast operation)
    callbacks = @callback_monitor.synchronize { @callbacks[event].dup }

    # Execute callbacks outside lock (safe, non-blocking)
    callbacks.each do |callback|
      callback.call(*args)
    rescue StandardError => e
      on_callback_error(event, callback, e)
    end
  end

  # Override hook for custom error handling
  def on_callback_error(event, callback, error)
    warn "[RubyLLM] Callback error in #{event}: #{error.class} - #{error.message}"
    warn error.backtrace.first(5).join("\n") if RubyLLM.config.debug
  end
end
```

### Update Call Sites

Replace all `@on[:event]&.call(...)` with `emit(:event, ...)`. This integrates with the concurrent tool execution implementation (see ALTERNATIVE_CONCURRENCY.md):

```ruby
# Before
def complete(&block)
  response = @provider.complete(...)
  @on[:new_message]&.call unless block
  # ...
  @on[:end_message]&.call(response)
end

# After
def complete(&block)
  response = @provider.complete(...)
  emit(:new_message) unless block
  # ...
  emit(:end_message, response)
end
```

**Tool Execution (aligned with concurrent execution design):**

```ruby
# Fires all events for a single tool (new_message, tool_call, tool_result, end_message)
def execute_single_tool_with_message(tool_call)
  emit(:new_message)
  result = execute_single_tool(tool_call)
  message = add_tool_result_message(tool_call, result)
  emit(:end_message, message)
  result
end

# Core tool execution - fires tool_call and tool_result events
def execute_single_tool(tool_call)
  emit(:tool_call, tool_call)

  tool_instance = tools[tool_call.name.to_sym]
  result = around_tool_execution(tool_call, tool_instance:) do
    tool_instance.call(tool_call.arguments)
  end

  emit(:tool_result, result)
  result
end

# Sequential execution (current behavior)
def execute_tools_sequentially(tool_calls)
  halt_result = nil

  tool_calls.each_value do |tool_call|
    result = execute_single_tool_with_message(tool_call)
    halt_result = result if result.is_a?(Tool::Halt)
  end

  halt_result
end

# Concurrent execution (fire-as-complete pattern)
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
  executor.call(tool_calls.values, max_concurrency: @max_concurrency) do |tool_call|
    execute_single_tool_with_message(tool_call)  # All events fire immediately per tool
  end
end
```

**Important**: In concurrent execution, ALL events (`new_message`, `tool_call`, `tool_result`, `end_message`) fire immediately as each tool completes. This provides real-time feedback - subscribers see progress as it happens, not batched at the end. The fire-as-complete pattern ensures responsive event handling.

## Design Decisions

### 1. FIFO Execution Order

Callbacks fire in registration order:

```ruby
chat.on_tool_call { puts "First" }
chat.on_tool_call { puts "Second" }
# Prints: "First", then "Second"
```

**Rationale:**
- Predictable and easy to reason about
- No priority complexity
- YAGNI - priority rarely needed

### 2. Error Isolation

One callback error doesn't block others:

```ruby
chat.on_tool_call { raise "Boom!" }
chat.on_tool_call { puts "Still fires" }  # This still executes
```

**Rationale:**
- Robustness: one bad actor doesn't break the system
- Debugging: all intended side effects still occur
- Override hook allows custom error handling

### 3. Safe Iteration

Always iterate over a copy:

```ruby
def emit(event, *args)
  callbacks = @callback_monitor.synchronize { @callbacks[event].dup }
  callbacks.each { |cb| cb.call(*args) }
end
```

**Why:**
- Self-unsubscribing callbacks work safely
- New subscriptions during emit don't cause issues
- No ConcurrentModificationException equivalent
- Minimal cost (copies array of references, not deep copy)

### 4. Thread and Fiber Safety

Uses Ruby's stdlib `Monitor` (not `Mutex`) for synchronization:

```ruby
@callback_monitor = Monitor.new
```

**Why Monitor over Mutex?**
- **Reentrant**: Same thread can acquire multiple times without deadlock
- **Critical for callbacks**: A callback might trigger another emit
- **Works with Async gem**: Ruby's fiber scheduler interface cooperates with Monitor
- **No deadlocks**: Fibers yield to event loop when blocked, not the entire thread

**Lock pattern - snapshot under lock:**

```ruby
def emit(event, *args)
  # Fast: acquire lock, copy array, release lock
  callbacks = @callback_monitor.synchronize { @callbacks[event].dup }

  # Slow: execute callbacks without holding lock
  callbacks.each { |cb| cb.call(*args) }
end
```

**Why this pattern?**
- Callbacks execute outside lock (can't cause deadlocks)
- Callbacks can safely subscribe/unsubscribe (modifies original array)
- Long-running callbacks don't block other threads/fibers
- Minimal lock contention

**Async gem compatibility:**

```ruby
require 'async'

Async do
  chat = RubyLLM.chat

  # Safe: Monitor cooperates with fiber scheduler
  chat.on_tool_call do |tc|
    # This works - Monitor already released before callback executes
    result = Async { fetch_from_api(tc) }.wait
    process(result)
  end
end
```

**Performance overhead:**
- Monitor acquisition: ~50-100 nanoseconds
- Array.dup: O(n) where n = number of callbacks (typically < 10)
- Total: < 1 microsecond per emit (negligible vs LLM API calls at 100ms-10s)

### 5. Concurrent Emit Behavior (Fire-As-Complete)

When using concurrent tool execution (`:async` or `:threads` mode), ALL events fire immediately as each tool completes:

```ruby
# Concurrent tool execution scenario
# Tool A, B, C execute in parallel
# Each tool fires: new_message → tool_call → tool_result → end_message
# These event groups interleave across tools
```

**Fire-as-complete pattern:**
- **Real-time feedback**: Events fire immediately when each tool finishes
- **No batching**: Don't wait for all tools to complete before firing events
- **Responsive**: Subscribers see progress as it happens

**Thread-safe emission guarantees:**
- **Snapshot isolation**: Each `emit()` gets its own copy of the callback list
- **No interleaving within event**: All callbacks for one emit complete before next emit's callbacks start (within same fiber/thread)
- **No ordering guarantee across tools**: Tool A's events may interleave with Tool B's events

**Important behavior:**

```ruby
chat = RubyLLM.chat(tool_concurrency: :async)

results = []
mutex = Mutex.new
chat.on_new_message { mutex.synchronize { results << "new" } }
chat.on_tool_call { |tc| mutex.synchronize { results << "call:#{tc.name}" } }
chat.on_tool_result { |r| mutex.synchronize { results << "result" } }
chat.on_end_message { |m| mutex.synchronize { results << "end" } }

# Execute 3 tools concurrently (A takes 1s, B takes 2s, C takes 0.5s)
# Possible output (C finishes first, then A, then B):
# ["new", "call:C", "result", "end", "new", "call:A", "result", "end", "new", "call:B", "result", "end"]
#
# Also possible (interleaved - A and B start before C finishes):
# ["new", "call:A", "new", "call:C", "result", "end", "new", "call:B", "result", "end", "result", "end"]
```

**Each tool's events fire in order** (new_message → tool_call → tool_result → end_message), but **different tools' events interleave** based on when they complete.

**Callback safety in concurrent execution:**

```ruby
# SAFE: Each callback gets its own data, Monitor protects subscription list
chat.on_tool_call do |tc|
  # tc is unique per emit, no shared state issues
  log("Tool: #{tc.name}")
end

# CAUTION: Shared mutable state requires external synchronization
results = []
mutex = Mutex.new
chat.on_tool_call do |tc|
  mutex.synchronize { results << tc.name }  # User's responsibility
end

# GOOD PATTERN: Use atomic operations
tool_count = Concurrent::AtomicFixnum.new(0)
chat.on_tool_result { |_| tool_count.increment }
```

The Monitor only protects the callback subscription list, not user data. If callbacks modify shared state during concurrent execution, users must provide their own synchronization.

### 6. No Implicit Context

Callbacks receive only the event data, not extra context:

```ruby
# Current (good)
emit(:tool_call, tool_call)

# Not this (overcomplicating)
emit(:tool_call, tool_call, context: { chat: self, timestamp: Time.now })
```

**Rationale:**
- Let closures capture what they need
- Cleaner API surface
- Ruby convention: pass what's needed, nothing more

```ruby
# Closures can capture chat reference
chat.on_tool_call do |tool_call|
  # 'chat' is captured from outer scope
  logger.info("Chat #{chat.object_id} called #{tool_call.name}")
end
```

### 7. Memory Management via Documentation

No weak references - document patterns instead:

```ruby
# GOOD: Lightweight closure
chat.on_tool_call { |tc| puts tc.name }

# GOOD: Unsubscribe when done
class TemporaryTracker
  def initialize(chat)
    @subscription = chat.subscribe(:tool_call) { |tc| track(tc) }
  end

  def stop
    @subscription.unsubscribe  # Release reference
  end
end

# BAD: Captures entire object graph
class HeavyService
  def initialize(chat, huge_dataset)
    @huge_dataset = huge_dataset  # 1GB of data
    chat.on_tool_call { |tc| @huge_dataset.process(tc) }  # Leak!
  end
end

# BETTER: Extract what's needed
class HeavyService
  def initialize(chat, huge_dataset)
    processor = huge_dataset.processor  # Just the processor
    chat.on_tool_call { |tc| processor.call(tc) }
  end
end
```

## Backwards Compatibility

### Zero Breaking Changes

| Feature | Before | After |
|---------|--------|-------|
| `on_*` return value | `self` (Chat) | `self` (Chat) |
| Chaining | Works | Still works |
| Multiple calls | Replaces previous | Appends (desired change) |
| Unsubscribe | Not possible | Via `subscribe()` |

### The Only Behavior Change

```ruby
# Before: Second replaces first
chat.on_tool_call { puts "A" }
chat.on_tool_call { puts "B" }
# Output: "B" only

# After: Both fire
chat.on_tool_call { puts "A" }
chat.on_tool_call { puts "B" }
# Output: "A", then "B"
```

This is the **desired behavior** - technically a breaking change, but users expect multiple handlers to work.

## Use Cases

### 1. Multiple Observers (Primary Use Case)

```ruby
# Logging
chat.on_tool_call { |tc| logger.info("Tool: #{tc.name}") }

# Metrics
chat.on_tool_call { |tc| metrics.increment("tool.#{tc.name}") }

# Audit
chat.on_tool_call { |tc| audit_log.record(tc) }

# All three fire for every tool call
```

### 2. One-Time Setup

```ruby
chat.once(:end_message) do |first_response|
  # Run setup only after first LLM response
  Analytics.track_conversation_started
end
```

### 3. Temporary Monitoring

```ruby
class PerformanceMonitor
  def initialize(chat)
    @start_times = {}
    @durations = []

    @subs = [
      chat.subscribe(:tool_call) { |tc| @start_times[tc.id] = Time.now },
      chat.subscribe(:tool_result) do |result|
        # Find corresponding start time
        # Record duration
      end
    ]
  end

  def report
    "Average tool duration: #{@durations.sum / @durations.size}ms"
  end

  def stop
    @subs.each(&:unsubscribe)
  end
end

monitor = PerformanceMonitor.new(chat)
chat.ask("Process data")
puts monitor.report
monitor.stop
```

### 4. Debugging

```ruby
if ENV['DEBUG']
  chat.on_new_message { puts "=== NEW MESSAGE ===" }
  chat.on_tool_call { |tc| puts "Calling: #{tc.name}(#{tc.arguments})" }
  chat.on_tool_result { |r| puts "Result: #{r.inspect}" }
  chat.on_end_message { |m| puts "Message added: #{m.role}" }
end
```

### 5. Plugin System

```ruby
module RubyLLM::Plugins
  class Telemetry
    def self.install(chat)
      chat.on_tool_call { |tc| track_tool_usage(tc) }
      chat.on_end_message { |m| track_token_usage(m) }
    end
  end

  class RateLimiter
    def self.install(chat)
      chat.subscribe(:tool_call) do |tc|
        wait_for_rate_limit(tc.name)
      end
    end
  end
end

# User installs multiple plugins
RubyLLM::Plugins::Telemetry.install(chat)
RubyLLM::Plugins::RateLimiter.install(chat)
# Both work independently
```

### 6. Layered Application Architecture

```ruby
class InfrastructureLayer
  def self.setup(chat)
    # Infrastructure concerns: logging, metrics, tracing
    chat.on_tool_call { |tc| Rails.logger.info("Tool: #{tc.name}") }
    chat.on_end_message { |m| StatsD.increment("llm.messages") }
  end
end

class BusinessLayer
  def self.setup(chat)
    # Business logic: validation, compliance
    chat.on_tool_result { |r| validate_compliance(r) }
  end
end

class DebugLayer
  def self.setup(chat)
    # Development helpers
    chat.on_tool_call { |tc| pp tc } if Rails.env.development?
  end
end

# All layers coexist
InfrastructureLayer.setup(chat)
BusinessLayer.setup(chat)
DebugLayer.setup(chat)
```

## Integration with Concurrent Tool Execution

This plan is designed to work seamlessly with the concurrent tool execution feature (see `ALTERNATIVE_CONCURRENCY.md`). Key integration points:

### Shared Foundation

Both features build on the same Chat class refactor:

```ruby
class Chat
  def initialize(...)
    # Multi-subscriber callbacks (this plan)
    @callbacks = { new_message: [], end_message: [], tool_call: [], tool_result: [] }
    @callback_monitor = Monitor.new

    # Concurrent execution (ALTERNATIVE_CONCURRENCY.md)
    @tool_concurrency = tool_concurrency
    @max_concurrency = max_concurrency
  end

  # Both features use emit() instead of @on[:]&.call()
  def execute_single_tool(tool_call)
    emit(:tool_call, tool_call)        # Multi-subscriber
    result = around_tool_execution(...) # Extensibility hook
    emit(:tool_result, result)          # Multi-subscriber
    result
  end
end
```

### Execution Order Semantics

```ruby
chat = RubyLLM.chat(tool_concurrency: :async, max_concurrency: 5)

# Register multiple subscribers
chat.on_tool_call { |tc| log(tc.name) }
chat.on_tool_result { |r| metrics.track(r) }
chat.on_end_message { |m| audit.record(m) }
```

**With fire-as-complete concurrent execution:**

1. **Per-tool event ordering** (guaranteed):
   - Each tool fires: `new_message` → `tool_call` → `tool_result` → `end_message`
   - All subscribers for each event notified in FIFO order
   - Events fire immediately as each tool completes

2. **Cross-tool event ordering** (non-deterministic):
   - All events from different tools may interleave
   - Order depends on when each tool finishes
   - User responsible for shared state synchronization

**Example timeline (3 tools, concurrent):**
```
Tool C (fast):   new_message → tool_call → tool_result → end_message
Tool A (medium): new_message → tool_call → tool_result → end_message
Tool B (slow):   new_message → tool_call → tool_result → end_message

Events fire as soon as each tool completes, not batched at the end.
```

### Implementation Order

**Recommended approach:**
1. Implement multi-subscriber callbacks first (this plan)
2. Then implement concurrent execution (ALTERNATIVE_CONCURRENCY.md)

**Why this order?**
- Concurrent execution depends on `emit()` method existing
- Single refactor of callback system instead of two passes
- Tests can verify callback behavior before adding concurrency complexity

### Cross-Feature Testing

```ruby
# Test both features together
describe "concurrent execution with multi-subscriber callbacks" do
  it "emits events to multiple subscribers during concurrent tool execution" do
    chat = RubyLLM.chat(tool_concurrency: :threads, max_concurrency: 2)

    tool_calls_logged = []
    metrics_tracked = []
    mutex = Mutex.new

    chat.on_tool_call do |tc|
      mutex.synchronize { tool_calls_logged << tc.name }
    end

    chat.on_tool_result do |result|
      mutex.synchronize { metrics_tracked << result }
    end

    # Execute concurrent tools
    # Both callbacks fire for each tool, possibly interleaved
    expect(tool_calls_logged.sort).to eq(["tool_a", "tool_b"])
    expect(metrics_tracked.size).to eq(2)
  end
end
```

## Implementation Checklist

### Phase 1: Core Changes
- [ ] Add `require 'monitor'` to Chat
- [ ] Add `Subscription` class with shared Monitor reference
- [ ] Change `@on = {}` to `@callbacks = { ... }` with arrays
- [ ] Add `@callback_monitor = Monitor.new` for thread safety
- [ ] Implement `subscribe(event, tag:, &block)` method (thread-safe)
- [ ] Implement `once(event, &block)` method
- [ ] Update `on_*` methods to use `subscribe()` internally
- [ ] Ensure `on_*` methods return `self` for chaining
- [ ] Add `emit(event, *args)` private method (snapshot under lock)
- [ ] Add `on_callback_error(event, callback, error)` hook
- [ ] Add `clear_callbacks(event = nil)` utility (thread-safe)
- [ ] Add `callback_count(event)` utility (thread-safe)

### Phase 2: Update Call Sites
- [ ] Replace `@on[:new_message]&.call` with `emit(:new_message)`
- [ ] Replace `@on[:end_message]&.call(msg)` with `emit(:end_message, msg)`
- [ ] Replace `@on[:tool_call]&.call(tc)` with `emit(:tool_call, tc)`
- [ ] Replace `@on[:tool_result]&.call(result)` with `emit(:tool_result, result)`
- [ ] Remove old `@on` hash initialization
- [ ] Update `execute_single_tool_with_message` to use `emit()` (fires all 4 events per tool)
- [ ] Update `execute_single_tool` to use `emit()` (fires tool_call and tool_result)
- [ ] Update `execute_tools_sequentially` to call `execute_single_tool_with_message`
- [ ] Update `execute_tools_concurrently` to use fire-as-complete pattern
- [ ] Ensure `complete()` uses `emit()` for streaming callbacks

### Phase 3: Testing
- [ ] Test multiple subscribers fire
- [ ] Test FIFO execution order
- [ ] Test unsubscribe works
- [ ] Test once() auto-unsubscribes
- [ ] Test error isolation (one error doesn't block others)
- [ ] Test safe iteration (unsubscribe during emit)
- [ ] Test backwards compatibility (`on_*` returns `self`)
- [ ] Test chaining still works
- [ ] Test clear_callbacks
- [ ] Test thread safety (concurrent subscribe/unsubscribe/emit)
- [ ] Test fiber safety (works correctly with Async gem)
- [ ] Test concurrent emit (multiple emits from different fibers/threads)
- [ ] Test fire-as-complete pattern (events fire immediately as tools finish)
- [ ] Test per-tool event ordering (new_message → tool_call → tool_result → end_message)
- [ ] Test cross-tool event interleaving (different tools' events may interleave)

### Phase 4: Documentation
- [ ] Update README with new multi-subscriber support
- [ ] Document `subscribe()` vs `on_*` API differences
- [ ] Document error handling patterns
- [ ] Document memory management best practices
- [ ] Add migration examples

## Files Changed

1. `lib/ruby_llm/chat.rb` - Core implementation (~80 lines added)
2. `spec/chat_callbacks_spec.rb` - Tests for new behavior
3. `docs/callbacks.md` - New documentation
4. `README.md` - Update examples

## Breaking Changes

**Technically one:**
- Multiple `on_*` calls now append instead of replace

**But this is the desired behavior** - most users expect multiple handlers to work. The only case that breaks is if someone explicitly relies on "replace" semantics (very rare).

## Benefits

### For RubyLLM
- ✅ Modern callback pattern (pub/sub)
- ✅ More useful for real applications
- ✅ Extensible plugin ecosystem
- ✅ Better debugging capabilities
- ✅ Minimal API surface change

### For Users
- ✅ **Logging + Metrics together**: No more choosing one or the other
- ✅ **Plugin-friendly**: Install multiple plugins that observe same events
- ✅ **Layered architecture**: Infrastructure, business, debug concerns coexist
- ✅ **Testing**: Add assertions without removing production code
- ✅ **Lifecycle management**: Unsubscribe when done

### For Library Authors
- ✅ Can register internal callbacks without blocking users
- ✅ Unsubscribe support for lifecycle management
- ✅ Custom error handling via override hook
- ✅ No more single-subscriber limitations

## Summary

This design provides:
1. **Zero API breaks** - All existing code continues to work
2. **Multi-subscriber support** - The primary goal
3. **Advanced features** - Unsubscribe, once(), error isolation
4. **Clean Ruby patterns** - Observer/Pub-Sub idiom
5. **Minimal changes** - ~100 lines of new code

The key insight: Keep `on_*` methods returning `self` for backwards compatibility, add `subscribe()` for advanced use cases. Simple things stay simple, complex things become possible.

```ruby
# Simple (unchanged API)
chat.on_tool_call { |tc| log(tc) }
    .on_tool_result { |r| track(r) }
    .ask("Hello")

# Advanced (new capability)
sub = chat.subscribe(:tool_call, tag: "metrics") { |tc| track(tc) }
# ... later
sub.unsubscribe
```
