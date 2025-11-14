# frozen_string_literal: true

require 'monitor'

module RubyLLM
  # Represents a conversation with an AI model
  class Chat
    include Enumerable

    # Represents an active subscription to a callback event.
    # Returned by {#subscribe} and can be used to unsubscribe later.
    class Subscription
      attr_reader :tag

      def initialize(callback_list, callback, monitor:, tag: nil)
        @callback_list = callback_list
        @callback = callback
        @monitor = monitor
        @tag = tag
        @active = true
      end

      # Removes this subscription from the callback list.
      # @return [Boolean] true if successfully unsubscribed, false if already inactive
      def unsubscribe # rubocop:disable Naming/PredicateMethod
        @monitor.synchronize do
          return false unless @active

          @callback_list.delete(@callback)
          @active = false
        end
        true
      end

      # Checks if this subscription is still active.
      # @return [Boolean] true if still subscribed
      def active?
        @monitor.synchronize do
          @active && @callback_list.include?(@callback)
        end
      end

      def inspect
        "#<#{self.class.name} tag=#{@tag.inspect} active=#{active?}>"
      end
    end

    attr_reader :model, :messages, :tools, :params, :headers, :schema, :tool_concurrency, :max_concurrency,
                :responses_session

    def initialize(model: nil, provider: nil, assume_model_exists: false, context: nil, # rubocop:disable Metrics/ParameterLists
                   tool_concurrency: nil, max_concurrency: nil)
      if assume_model_exists && !provider
        raise ArgumentError, 'Provider must be specified if assume_model_exists is true'
      end

      @context = context
      @config = context&.config || RubyLLM.config
      model_id = model || @config.default_model
      with_model(model_id, provider: provider, assume_exists: assume_model_exists)
      @temperature = nil
      @messages = []
      @messages_mutex = Mutex.new
      @tools = {}
      @params = {}
      @headers = {}
      @schema = nil

      # Concurrent tool execution settings
      @tool_concurrency = tool_concurrency
      @max_concurrency = max_concurrency

      # Responses API state
      @responses_api_config = nil
      @responses_session = nil

      # Multi-subscriber callback system
      @callbacks = {
        new_message: [],
        end_message: [],
        tool_call: [],
        tool_result: []
      }
      @callback_monitor = Monitor.new
    end

    def ask(message = nil, with: nil, &)
      add_message role: :user, content: build_content(message, with)
      complete(&)
    end

    alias say ask

    def with_instructions(instructions, replace: false)
      @messages = @messages.reject { |msg| msg.role == :system } if replace

      add_message role: :system, content: instructions
      self
    end

    def with_tool(tool)
      tool_instance = tool.is_a?(Class) ? tool.new : tool
      @tools[tool_instance.name.to_sym] = tool_instance
      self
    end

    def with_tools(*tools, replace: false)
      @tools.clear if replace
      tools.compact.each { |tool| with_tool tool }
      self
    end

    def with_model(model_id, provider: nil, assume_exists: false)
      @model, @provider = Models.resolve(model_id, provider:, assume_exists:, config: @config)
      @connection = @provider.connection
      self
    end

    def with_temperature(temperature)
      @temperature = temperature
      self
    end

    def with_context(context)
      @context = context
      @config = context.config
      with_model(@model.id, provider: @provider.slug, assume_exists: true)
      self
    end

    def with_params(**params)
      @params = params
      self
    end

    def with_headers(**headers)
      @headers = headers
      self
    end

    def with_schema(schema)
      schema_instance = schema.is_a?(Class) ? schema.new : schema

      # Accept both RubyLLM::Schema instances and plain JSON schemas
      @schema = if schema_instance.respond_to?(:to_json_schema)
                  schema_instance.to_json_schema[:schema]
                else
                  schema_instance
                end

      self
    end

    # Configures concurrent tool execution for this chat.
    #
    # @param mode [Symbol, nil] Concurrency mode (:async, :threads, or nil for sequential)
    # @param max [Integer, nil] Maximum number of concurrent tool executions
    # @return [self] for chaining
    #
    # @example
    #   chat.with_tool_concurrency(:async, max: 5)
    #        .with_tools(Weather, Stock, Currency)
    #        .ask("Get weather, stock price, and currency rate")
    def with_tool_concurrency(mode = nil, max: nil)
      @tool_concurrency = mode unless mode.nil?
      @max_concurrency = max if max
      self
    end

    # Enables OpenAI Responses API for this chat.
    # Switches from chat/completions to the v1/responses endpoint.
    #
    # @param stateful [Boolean] Use previous_response_id for efficient multi-turn (default: false)
    # @param store [Boolean] Store responses on OpenAI server (default: true)
    # @param truncation [Symbol] Truncation strategy (default: :disabled)
    # @param include [Array<Symbol>] Additional data to include (e.g., [:reasoning_encrypted_content])
    # @return [self] for chaining
    #
    # @example Basic usage
    #   chat.with_responses_api.ask("Hello")
    #
    # @example Stateful mode for token efficiency
    #   chat.with_responses_api(stateful: true).ask("Hello")
    #
    # @example With custom configuration
    #   chat.with_responses_api(
    #     stateful: true,
    #     truncation: :auto,
    #     include: [:reasoning_encrypted_content]
    #   ).ask("Complex reasoning task")
    def with_responses_api(stateful: false, store: true, truncation: :disabled, include: [], **options)
      unless @provider.is_a?(Providers::OpenAI)
        raise ArgumentError, 'with_responses_api is only supported for OpenAI providers'
      end

      @responses_api_config = {
        stateful: stateful,
        store: store,
        truncation: truncation,
        include: include,
        service_tier: options[:service_tier],
        max_tool_calls: options[:max_tool_calls]
      }

      # Initialize session if not already present
      @responses_session ||= ResponsesSession.new

      # Switch to OpenAIResponses provider if currently using standard OpenAI
      unless @provider.is_a?(Providers::OpenAIResponses)
        @provider = Providers::OpenAIResponses.new(@config, @responses_session, @responses_api_config)
        @connection = @provider.connection
      end

      self
    end

    # Restores a Responses API session from previously saved state.
    # Used for persisting sessions across requests (e.g., Rails).
    #
    # @param session_data [Hash] Session data from ResponsesSession#to_h
    # @return [self] for chaining
    def restore_responses_session(session_data)
      @responses_session = ResponsesSession.from_h(session_data)

      # Update provider session if already using Responses API
      if @provider.is_a?(Providers::OpenAIResponses)
        @provider = Providers::OpenAIResponses.new(@config, @responses_session, @responses_api_config || {})
        @connection = @provider.connection
      end

      self
    end

    # Checks if the Responses API is currently enabled for this chat.
    #
    # @return [Boolean] true if using OpenAI Responses API
    def responses_api_enabled?
      @provider.is_a?(Providers::OpenAIResponses)
    end

    # Subscribes to an event with the given block.
    # Returns a {Subscription} that can be used to unsubscribe.
    #
    # @param event [Symbol] The event to subscribe to (:new_message, :end_message, :tool_call, :tool_result)
    # @param tag [String, nil] Optional tag for debugging/identification
    # @yield The block to call when the event fires
    # @return [Subscription] An object that can be used to unsubscribe
    # @raise [ArgumentError] if event is not recognized
    #
    # @example
    #   sub = chat.subscribe(:tool_call, tag: "metrics") { |tc| track(tc) }
    #   # ... later
    #   sub.unsubscribe
    def subscribe(event, tag: nil, &block)
      @callback_monitor.synchronize do
        unless @callbacks.key?(event)
          raise ArgumentError, "Unknown event: #{event}. Valid events: #{@callbacks.keys.join(', ')}"
        end

        @callbacks[event] << block
        Subscription.new(@callbacks[event], block, monitor: @callback_monitor, tag: tag)
      end
    end

    # Subscribes to an event that automatically unsubscribes after firing once.
    #
    # @param event [Symbol] The event to subscribe to
    # @param tag [String, nil] Optional tag for debugging/identification
    # @yield The block to call when the event fires (once)
    # @return [Subscription] An object that can be used to unsubscribe before it fires
    #
    # @example
    #   chat.once(:end_message) { |msg| setup_initial_state(msg) }
    def once(event, tag: nil, &block)
      subscription = nil
      wrapper = lambda do |*args|
        subscription&.unsubscribe
        block.call(*args)
      end
      subscription = subscribe(event, tag: tag, &wrapper)
    end

    # Registers a callback for when a new message starts being generated.
    # Multiple callbacks can be registered and all will fire in registration order.
    #
    # @yield Block called when a new message starts
    # @return [self] for chaining
    def on_new_message(&)
      subscribe(:new_message, &)
      self
    end

    # Registers a callback for when a message is complete.
    # Multiple callbacks can be registered and all will fire in registration order.
    #
    # @yield [Message] Block called with the completed message
    # @return [self] for chaining
    def on_end_message(&)
      subscribe(:end_message, &)
      self
    end

    # Registers a callback for when a tool is called.
    # Multiple callbacks can be registered and all will fire in registration order.
    #
    # @yield [ToolCall] Block called with the tool call object
    # @return [self] for chaining
    def on_tool_call(&)
      subscribe(:tool_call, &)
      self
    end

    # Registers a callback for when a tool returns a result.
    # Multiple callbacks can be registered and all will fire in registration order.
    #
    # @yield [ToolCall, Object] Block called with the tool call and its result
    # @return [self] for chaining
    def on_tool_result(&)
      subscribe(:tool_result, &)
      self
    end

    # Clears all callbacks for the specified event, or all events if none specified.
    #
    # @param event [Symbol, nil] The event to clear callbacks for, or nil for all events
    # @return [self] for chaining
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

    # Returns the number of callbacks registered for the specified event.
    #
    # @param event [Symbol, nil] The event to count callbacks for, or nil for all events
    # @return [Integer, Hash] Count for specific event, or hash of counts for all events
    def callback_count(event = nil)
      @callback_monitor.synchronize do
        if event
          @callbacks[event]&.size || 0
        else
          @callbacks.transform_values(&:size)
        end
      end
    end

    def each(&)
      messages.each(&)
    end

    def complete(&)
      response = @provider.complete(
        messages,
        tools: @tools,
        temperature: @temperature,
        model: @model,
        params: @params,
        headers: @headers,
        schema: @schema,
        &wrap_streaming_block(&)
      )

      emit(:new_message) unless block_given?
      update_responses_session(response)
      parse_schema_response(response)

      if response.tool_call?
        execute_tool_call_sequence(response, &)
      else
        add_message response
        emit(:end_message, response)
        response
      end
    end

    # Adds a message to the conversation history.
    # Thread-safe: uses mutex to protect message array.
    #
    # @param message_or_attributes [Message, Hash] A Message object or hash of attributes
    # @return [Message] The added message
    def add_message(message_or_attributes)
      message = message_or_attributes.is_a?(Message) ? message_or_attributes : Message.new(message_or_attributes)
      @messages_mutex.synchronize do
        @messages << message
      end
      message
    end

    # Returns a thread-safe, frozen snapshot of the message history.
    # Use this for safe reading when concurrent operations may be modifying messages.
    #
    # @return [Array<Message>] Frozen copy of the messages array
    def message_history
      @messages_mutex.synchronize { @messages.dup.freeze }
    end

    # Replaces the entire message history with new messages.
    # Thread-safe: uses mutex to protect message array.
    #
    # @param new_messages [Array<Message, Hash>] New messages to set
    # @return [self] for chaining
    def set_messages(new_messages) # rubocop:disable Naming/AccessorMethodName
      @messages_mutex.synchronize do
        @messages.clear
        new_messages.each do |msg|
          @messages << (msg.is_a?(Message) ? msg : Message.new(msg))
        end
      end
      self
    end

    # Creates a snapshot of the current message history for checkpointing.
    # Thread-safe: uses mutex to protect message array.
    #
    # @return [Array<Message>] Duplicated messages for restoration later
    def snapshot_messages
      @messages_mutex.synchronize { @messages.map(&:dup) }
    end

    # Restores messages from a previously taken snapshot.
    #
    # @param snapshot [Array<Message>] Previously saved message snapshot
    # @return [self] for chaining
    def restore_messages(snapshot)
      set_messages(snapshot)
    end

    # Clears messages from the conversation history.
    # Thread-safe: uses mutex to protect message array.
    #
    # @param preserve_system_prompt [Boolean] if true (default), keeps system messages
    # @return [self] for chaining
    def reset_messages!(preserve_system_prompt: true)
      @messages_mutex.synchronize do
        if preserve_system_prompt
          @messages.select! { |m| m.role == :system }
        else
          @messages.clear
        end
      end
      self
    end

    # Wraps operations in a transaction for rollback on failure.
    # If an exception is raised, all messages added since the transaction started are removed.
    # This ensures Chat state remains valid even on cancellation or errors.
    #
    # Uses O(1) memory (just tracks index, no array duplication).
    #
    # @yield Block to execute within the transaction
    # @return [Object] Result of the block
    # @raise Re-raises any exception after rolling back
    def with_message_transaction
      start_index = @messages_mutex.synchronize { @messages.size }

      begin
        yield
      rescue StandardError => e
        # Truncate back to where we started (O(1) operation)
        @messages_mutex.synchronize do
          @messages.slice!(start_index..-1)
        end
        raise e
      end
    end

    # Checks if the last tool call has all corresponding results.
    # Useful for diagnosing incomplete Chat state after interruptions.
    #
    # @return [Boolean] true if all tool calls have results
    def tool_results_complete? # rubocop:disable Metrics/PerceivedComplexity
      return true unless messages.any?

      last_assistant = messages.reverse.find do |m|
        m.role == :assistant && m.respond_to?(:tool_calls) && m.tool_calls&.any?
      end
      return true unless last_assistant

      expected_ids = last_assistant.tool_calls.keys.to_set
      actual_ids = messages.select { |m| m.role == :tool }.filter_map(&:tool_call_id).to_set

      expected_ids.subset?(actual_ids)
    end

    # Removes incomplete tool call sequence if interrupted.
    # Call this to repair Chat state after cancellation/exception.
    #
    # @return [self] for chaining
    def repair_incomplete_tool_calls! # rubocop:disable Metrics/PerceivedComplexity
      return self if tool_results_complete?

      @messages_mutex.synchronize do
        # Remove partial tool results
        @messages.pop while @messages.last&.role == :tool

        # Remove the incomplete assistant message with tool_calls
        last = @messages.last
        @messages.pop if last&.role == :assistant && last.respond_to?(:tool_calls) && last.tool_calls&.any?
      end
      self
    end

    def instance_variables
      super - %i[@connection @config @messages_mutex @callback_monitor]
    end

    private

    def wrap_streaming_block(&block)
      return nil unless block_given?

      first_chunk_received = false

      proc do |chunk|
        # Emit new_message on first content chunk
        unless first_chunk_received
          first_chunk_received = true
          emit(:new_message)
        end

        block.call chunk
      end
    end

    def handle_tool_calls(response, &)
      halt_result = if concurrent_tools?
                      execute_tools_concurrently(response.tool_calls)
                    else
                      execute_tools_sequentially(response.tool_calls)
                    end

      halt_result || complete(&)
    end

    # Executes tool call sequence within a transaction for atomicity.
    # If interrupted or an error occurs, the assistant message and any partial
    # tool results are rolled back, keeping Chat state valid.
    def execute_tool_call_sequence(response, &block)
      with_message_transaction do
        # Add assistant message (inside transaction)
        add_message response
        emit(:end_message, response)

        # Execute tools and potentially recurse
        handle_tool_calls(response, &block)
      end
    end

    # Executes tools sequentially (one at a time).
    # Each tool fires all events and adds its message immediately.
    def execute_tools_sequentially(tool_calls)
      halt_result = nil

      tool_calls.each_value do |tool_call|
        result = execute_single_tool_with_message(tool_call)
        halt_result = result if result.is_a?(Tool::Halt)
      end

      halt_result
    end

    # Executes tools concurrently using the configured executor.
    # Uses hybrid pattern: fires events immediately, adds messages atomically.
    def execute_tools_concurrently(tool_calls)
      results = parallel_execute_tools(tool_calls)
      add_tool_results_atomically(tool_calls, results)
      find_first_halt(tool_calls, results)
    end

    # Executes tools in parallel using the registered executor.
    def parallel_execute_tools(tool_calls)
      executor = RubyLLM.tool_executors[@tool_concurrency]
      raise ArgumentError, "Unknown tool executor: #{@tool_concurrency}" unless executor

      executor.call(tool_calls.values, max_concurrency: @max_concurrency) do |tool_call|
        execute_single_tool_with_events(tool_call)
      end
    end

    # Executes a single tool with all events and immediate message addition.
    # Used for sequential execution.
    def execute_single_tool_with_message(tool_call)
      emit(:new_message)
      result = execute_single_tool(tool_call)
      emit(:tool_result, tool_call, result)
      message = add_tool_result_message(tool_call, result)
      emit(:end_message, message)
      result
    end

    # Executes a single tool with events but without message addition.
    # Used for concurrent execution (messages added atomically later).
    def execute_single_tool_with_events(tool_call)
      emit(:new_message)
      result = execute_single_tool(tool_call)
      emit(:tool_result, tool_call, result)
      result
    end

    # Core tool execution: fires tool_call event, runs the tool with extensibility hook.
    def execute_single_tool(tool_call)
      emit(:tool_call, tool_call)

      tool_instance = tools[tool_call.name.to_sym]
      around_tool_execution(tool_call, tool_instance: tool_instance) do
        tool_instance.call(tool_call.arguments)
      end
    end

    # Creates and adds a tool result message.
    def add_tool_result_message(tool_call, result)
      tool_payload = result.is_a?(Tool::Halt) ? result.content : result
      content = content_like?(tool_payload) ? tool_payload : tool_payload.to_s
      add_message role: :tool, content: content, tool_call_id: tool_call.id
    end

    # Updates the Responses API session with the response ID if applicable.
    def update_responses_session(response)
      return unless responses_api_enabled?
      return unless response.respond_to?(:response_id) && response.response_id

      @responses_session.update(response.response_id)
    end

    # Parses JSON schema response content if applicable.
    def parse_schema_response(response)
      return unless @schema && response.content.is_a?(String)

      response.content = JSON.parse(response.content)
    rescue JSON::ParserError
      # If parsing fails, keep content as string
    end

    # Adds all tool result messages atomically to ensure Chat state consistency.
    # This prevents partial results that would make the Chat invalid for LLM APIs.
    def add_tool_results_atomically(tool_calls, results)
      messages = []

      @messages_mutex.synchronize do
        tool_calls.each_key do |id|
          tool_call = tool_calls[id]
          result = results[id]

          tool_payload = result.is_a?(Tool::Halt) ? result.content : result
          content = content_like?(tool_payload) ? tool_payload : tool_payload.to_s
          message = Message.new(role: :tool, content: content, tool_call_id: tool_call.id)
          @messages << message
          messages << message
        end
      end

      # Fire events outside mutex to prevent blocking
      messages.each { |msg| emit(:end_message, msg) }
    end

    # Finds the first halt result by request order (not completion order).
    def find_first_halt(tool_calls, results)
      tool_calls.each_key do |id|
        result = results[id]
        return result if result.is_a?(Tool::Halt)
      end
      nil
    end

    # Extensibility hook for wrapping tool execution.
    # Override in subclass to add resource management, caching, instrumentation, etc.
    #
    # @param tool_call [ToolCall] The tool call being executed
    # @param tool_instance [Tool] The tool instance
    # @yield Executes the actual tool
    # @return [Object] Tool result (from yield or short-circuit)
    def around_tool_execution(_tool_call, tool_instance:) # rubocop:disable Lint/UnusedMethodArgument
      yield
    end

    def build_content(message, attachments)
      return message if content_like?(message)

      Content.new(message, attachments)
    end

    def content_like?(object)
      object.is_a?(Content) || object.is_a?(Content::Raw)
    end

    def concurrent_tools?
      @tool_concurrency && @tool_concurrency != :sequential
    end

    # Emits an event to all registered subscribers.
    # Callbacks are executed in registration order (FIFO).
    # Errors in callbacks are isolated - one failing callback doesn't prevent others from running.
    #
    # @param event [Symbol] The event to emit
    # @param args [Array] Arguments to pass to each callback
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

    # Hook for custom error handling when a callback raises an exception.
    # Override this method in a subclass to customize error behavior.
    #
    # @param event [Symbol] The event that was being emitted
    # @param callback [Proc] The callback that raised the error
    # @param error [StandardError] The error that was raised
    def on_callback_error(event, _callback, error)
      warn "[RubyLLM] Callback error in #{event}: #{error.class} - #{error.message}"
      warn error.backtrace.first(5).join("\n") if @config.respond_to?(:debug) && @config.debug
    end
  end
end
