# frozen_string_literal: true

require 'spec_helper'

# rubocop:disable Security/NoReflectionMethods
RSpec.describe RubyLLM::Chat do
  before(:all) do # rubocop:disable RSpec/BeforeAfterAll
    RubyLLM.configure do |config|
      config.openai_api_key = 'test-key'
    end
  end

  describe 'multi-subscriber callback system' do
    let(:chat) { described_class.new(model: 'gpt-4o-mini') }

    describe '#subscribe' do
      it 'returns a Subscription object' do
        sub = chat.subscribe(:new_message) { 'test' }
        expect(sub).to be_a(described_class::Subscription)
      end

      it 'allows multiple subscribers for the same event' do
        chat.subscribe(:tool_call) { 'first' }
        chat.subscribe(:tool_call) { 'second' }
        expect(chat.callback_count(:tool_call)).to eq(2)
      end

      it 'raises ArgumentError for unknown events' do
        expect { chat.subscribe(:unknown_event) { 'test' } }
          .to raise_error(ArgumentError, /Unknown event/)
      end

      it 'supports tagging subscriptions' do
        sub = chat.subscribe(:new_message, tag: 'metrics') { 'test' }
        expect(sub.tag).to eq('metrics')
      end
    end

    describe '#once' do
      it 'fires the callback only once' do
        call_count = 0
        chat.once(:new_message) { call_count += 1 }

        chat.send(:emit, :new_message)
        chat.send(:emit, :new_message)
        chat.send(:emit, :new_message)

        expect(call_count).to eq(1)
      end

      it 'returns a Subscription that can be unsubscribed before firing' do
        sub = chat.once(:tool_call) { 'test' }
        expect(sub.active?).to be true

        sub.unsubscribe
        expect(sub.active?).to be false
      end
    end

    describe '#on_* methods' do
      it 'returns self for chaining' do
        result = chat.on_new_message { 'a' }
                     .on_end_message { 'b' }
                     .on_tool_call { 'c' }
                     .on_tool_result { 'd' }
        expect(result).to eq(chat)
      end

      it 'allows multiple callbacks to be registered' do
        chat.on_tool_call { 'first' }
        chat.on_tool_call { 'second' }
        chat.on_tool_call { 'third' }

        expect(chat.callback_count(:tool_call)).to eq(3)
      end
    end

    describe 'Subscription' do
      let(:subscription) { chat.subscribe(:new_message) { 'test' } }

      it 'tracks active status' do
        expect(subscription.active?).to be true
      end

      it 'can unsubscribe' do
        result = subscription.unsubscribe
        expect(result).to be true
        expect(subscription.active?).to be false
      end

      it 'removes callback from list on unsubscribe' do
        subscription # Ensure subscription is created first
        expect(chat.callback_count(:new_message)).to eq(1)
        subscription.unsubscribe
        expect(chat.callback_count(:new_message)).to eq(0)
      end

      it 'returns false when unsubscribing twice' do
        subscription.unsubscribe
        result = subscription.unsubscribe
        expect(result).to be false
      end

      it 'has informative inspect output' do
        expect(subscription.inspect).to include('Subscription')
        expect(subscription.inspect).to include('active=true')
      end
    end

    describe '#emit' do
      it 'fires all subscribers in registration order (FIFO)' do
        results = []
        chat.on_new_message { results << 'first' }
        chat.on_new_message { results << 'second' }
        chat.on_new_message { results << 'third' }

        chat.send(:emit, :new_message)

        expect(results).to eq(%w[first second third])
      end

      it 'passes arguments to callbacks' do
        received_args = nil
        chat.on_tool_call { |tc| received_args = tc }

        test_arg = instance_double(RubyLLM::ToolCall, name: 'test_tool')
        chat.send(:emit, :tool_call, test_arg)

        expect(received_args).to eq(test_arg)
      end

      it 'isolates errors in callbacks' do
        results = []
        chat.on_tool_call { raise 'Boom!' }
        chat.on_tool_call { results << 'still fires' }

        expect { chat.send(:emit, :tool_call, instance_double(RubyLLM::ToolCall)) }.not_to raise_error
        expect(results).to eq(['still fires'])
      end

      it 'allows safe iteration when callbacks unsubscribe themselves' do
        results = []
        sub = nil

        sub = chat.subscribe(:new_message) do
          results << 'self-unsubscribe'
          sub.unsubscribe
        end
        chat.on_new_message { results << 'second' }

        expect { chat.send(:emit, :new_message) }.not_to raise_error
        expect(results).to eq(%w[self-unsubscribe second])
      end
    end

    describe '#clear_callbacks' do
      before do
        chat.on_new_message { 'a' }
        chat.on_tool_call { 'b' }
        chat.on_end_message { 'c' }
      end

      it 'clears callbacks for a specific event' do
        chat.clear_callbacks(:tool_call)

        expect(chat.callback_count(:tool_call)).to eq(0)
        expect(chat.callback_count(:new_message)).to eq(1)
      end

      it 'clears all callbacks when no event specified' do
        chat.clear_callbacks

        expect(chat.callback_count(:new_message)).to eq(0)
        expect(chat.callback_count(:tool_call)).to eq(0)
        expect(chat.callback_count(:end_message)).to eq(0)
      end

      it 'returns self for chaining' do
        result = chat.clear_callbacks
        expect(result).to eq(chat)
      end
    end

    describe '#callback_count' do
      it 'returns count for specific event' do
        chat.on_tool_call { 'a' }
        chat.on_tool_call { 'b' }
        expect(chat.callback_count(:tool_call)).to eq(2)
      end

      it 'returns hash of all counts when no event specified' do
        chat.on_new_message { 'a' }
        chat.on_tool_call { 'b' }
        chat.on_tool_call { 'c' }

        counts = chat.callback_count
        expect(counts).to be_a(Hash)
        expect(counts[:new_message]).to eq(1)
        expect(counts[:tool_call]).to eq(2)
        expect(counts[:end_message]).to eq(0)
        expect(counts[:tool_result]).to eq(0)
      end
    end
  end

  describe 'thread-safe message management' do
    let(:chat) { described_class.new(model: 'gpt-4o-mini') }

    describe '#add_message' do
      it 'adds messages to the history' do
        chat.add_message(role: :user, content: 'Hello')
        expect(chat.messages.size).to eq(1)
        expect(chat.messages.first.content).to eq('Hello')
      end

      it 'returns the added message' do
        message = chat.add_message(role: :user, content: 'Test')
        expect(message).to be_a(RubyLLM::Message)
        expect(message.content).to eq('Test')
      end
    end

    describe '#message_history' do
      it 'returns a frozen copy of messages' do
        chat.add_message(role: :user, content: 'Hello')
        history = chat.message_history

        expect(history).to be_frozen
        expect(history.size).to eq(1)
      end

      it 'does not affect original when modified' do
        chat.add_message(role: :user, content: 'Hello')
        history = chat.message_history

        # Original should be unaffected by attempts to modify the copy
        expect { history << 'test' }.to raise_error(FrozenError)
        expect(chat.messages.size).to eq(1)
      end
    end

    describe '#set_messages' do
      it 'replaces all messages' do
        chat.add_message(role: :user, content: 'First')
        chat.set_messages([
                            { role: :user, content: 'New1' },
                            { role: :assistant, content: 'New2' }
                          ])

        expect(chat.messages.size).to eq(2)
        expect(chat.messages.first.content).to eq('New1')
      end

      it 'returns self for chaining' do
        result = chat.set_messages([])
        expect(result).to eq(chat)
      end
    end

    describe '#snapshot_messages' do
      it 'creates a copy of messages for checkpointing' do
        chat.add_message(role: :user, content: 'Hello')
        snapshot = chat.snapshot_messages

        expect(snapshot.size).to eq(1)
        expect(snapshot.first.content).to eq('Hello')
      end

      it 'is independent of the original' do
        chat.add_message(role: :user, content: 'Hello')
        snapshot = chat.snapshot_messages

        chat.add_message(role: :assistant, content: 'Hi')
        expect(snapshot.size).to eq(1)
      end
    end

    describe '#restore_messages' do
      it 'restores from a snapshot' do
        chat.add_message(role: :user, content: 'Hello')
        snapshot = chat.snapshot_messages

        chat.add_message(role: :assistant, content: 'Hi')
        chat.add_message(role: :user, content: 'How are you?')

        chat.restore_messages(snapshot)
        expect(chat.messages.size).to eq(1)
        expect(chat.messages.first.content).to eq('Hello')
      end

      it 'returns self for chaining' do
        result = chat.restore_messages([])
        expect(result).to eq(chat)
      end
    end

    describe '#reset_messages!' do
      it 'clears non-system messages by default' do
        chat.add_message(role: :user, content: 'Hello')
        chat.reset_messages!
        expect(chat.messages).to be_empty
      end

      it 'preserves system messages by default' do
        chat.add_message(role: :system, content: 'You are helpful')
        chat.add_message(role: :user, content: 'Hello')
        chat.add_message(role: :assistant, content: 'Hi there')

        chat.reset_messages!

        expect(chat.messages.size).to eq(1)
        expect(chat.messages.first.role).to eq(:system)
        expect(chat.messages.first.content).to eq('You are helpful')
      end

      it 'preserves multiple system messages' do
        chat.add_message(role: :system, content: 'First instruction')
        chat.add_message(role: :system, content: 'Second instruction')
        chat.add_message(role: :user, content: 'Hello')

        chat.reset_messages!

        expect(chat.messages.size).to eq(2)
        expect(chat.messages.map(&:role)).to all(eq(:system))
      end

      it 'clears all messages including system when preserve_system_prompt is false' do
        chat.add_message(role: :system, content: 'You are helpful')
        chat.add_message(role: :user, content: 'Hello')

        chat.reset_messages!(preserve_system_prompt: false)

        expect(chat.messages).to be_empty
      end

      it 'returns self for chaining' do
        result = chat.reset_messages!
        expect(result).to eq(chat)
      end
    end
  end

  describe 'concurrency configuration' do
    it 'accepts concurrency options in constructor' do
      chat = described_class.new(
        model: 'gpt-4o-mini',
        tool_concurrency: :async,
        max_concurrency: 5
      )

      expect(chat.tool_concurrency).to eq(:async)
      expect(chat.max_concurrency).to eq(5)
    end

    describe '#with_tool_concurrency' do
      let(:chat) { described_class.new(model: 'gpt-4o-mini') }

      it 'sets concurrency mode' do
        chat.with_tool_concurrency(:threads)
        expect(chat.tool_concurrency).to eq(:threads)
      end

      it 'sets max concurrency' do
        chat.with_tool_concurrency(:async, max: 10)
        expect(chat.max_concurrency).to eq(10)
      end

      it 'returns self for chaining' do
        result = chat.with_tool_concurrency(:threads)
        expect(result).to eq(chat)
      end
    end
  end

  describe 'message transaction support' do
    let(:chat) { described_class.new(model: 'gpt-4o-mini') }

    describe '#with_message_transaction' do
      it 'rolls back on exception' do
        chat.add_message(role: :user, content: 'Before')

        expect do
          chat.with_message_transaction do
            chat.add_message(role: :assistant, content: 'During')
            raise 'Test error'
          end
        end.to raise_error('Test error')

        expect(chat.messages.size).to eq(1)
        expect(chat.messages.first.content).to eq('Before')
      end

      it 'keeps changes on success' do
        chat.add_message(role: :user, content: 'Before')

        chat.with_message_transaction do
          chat.add_message(role: :assistant, content: 'Success')
        end

        expect(chat.messages.size).to eq(2)
      end

      it 'returns the block result' do
        result = chat.with_message_transaction { 'result' }
        expect(result).to eq('result')
      end
    end

    describe '#tool_results_complete?' do
      it 'returns true when no messages' do
        expect(chat.tool_results_complete?).to be true
      end

      it 'returns true when no tool calls' do
        chat.add_message(role: :user, content: 'Hello')
        chat.add_message(role: :assistant, content: 'Hi')
        expect(chat.tool_results_complete?).to be true
      end
    end
  end

  describe '#around_tool_execution' do
    let(:chat) { described_class.new(model: 'gpt-4o-mini') }

    let(:test_tool) do
      Class.new(RubyLLM::Tool) do
        description 'A test tool'

        def name
          'test_tool'
        end

        def execute
          'original_result'
        end
      end
    end

    before do
      chat.with_tool(test_tool)
    end

    it 'returns self for chaining' do
      result = chat.around_tool_execution { |_tc, _ti, exec| exec.call }
      expect(result).to eq(chat)
    end

    it 'wraps tool execution with custom logic' do
      call_order = []

      chat.around_tool_execution do |tool_call, _tool_instance, execute|
        call_order << "before:#{tool_call.name}"
        result = execute.call
        call_order << "after:#{result}"
        result
      end

      tool_call = RubyLLM::ToolCall.new(id: 'call_123', name: 'test_tool', arguments: {})
      result = chat.send(:execute_single_tool, tool_call)

      expect(call_order).to eq(%w[before:test_tool after:original_result])
      expect(result).to eq('original_result')
    end

    it 'provides access to tool_call and tool_instance' do
      received_tool_call = nil
      received_tool_instance = nil

      chat.around_tool_execution do |tool_call, tool_instance, execute|
        received_tool_call = tool_call
        received_tool_instance = tool_instance
        execute.call
      end

      tool_call = RubyLLM::ToolCall.new(id: 'call_456', name: 'test_tool', arguments: {})
      chat.send(:execute_single_tool, tool_call)

      expect(received_tool_call).to eq(tool_call)
      expect(received_tool_instance).to be_a(test_tool)
      expect(received_tool_instance.name).to eq('test_tool')
    end

    it 'allows modifying the result' do
      chat.around_tool_execution do |_tc, _ti, execute|
        original = execute.call
        "modified:#{original}"
      end

      tool_call = RubyLLM::ToolCall.new(id: 'call_789', name: 'test_tool', arguments: {})
      result = chat.send(:execute_single_tool, tool_call)

      expect(result).to eq('modified:original_result')
    end

    it 'allows skipping execution entirely' do
      chat.around_tool_execution do |_tc, _ti, _execute|
        'cached_result'
      end

      tool_call = RubyLLM::ToolCall.new(id: 'call_skip', name: 'test_tool', arguments: {})
      result = chat.send(:execute_single_tool, tool_call)

      expect(result).to eq('cached_result')
    end

    it 'replaces previous hook when called multiple times' do
      chat.around_tool_execution { |_tc, _ti, _exec| 'first' }
      chat.around_tool_execution { |_tc, _ti, _exec| 'second' }

      tool_call = RubyLLM::ToolCall.new(id: 'call_multi', name: 'test_tool', arguments: {})
      result = chat.send(:execute_single_tool, tool_call)

      expect(result).to eq('second')
    end

    it 'works without any hook set' do
      tool_call = RubyLLM::ToolCall.new(id: 'call_none', name: 'test_tool', arguments: {})
      result = chat.send(:execute_single_tool, tool_call)

      expect(result).to eq('original_result')
    end

    it 'can implement caching pattern' do
      cache = {}

      chat.around_tool_execution do |tool_call, _tool_instance, execute|
        cache_key = [tool_call.name, tool_call.arguments].hash
        cache[cache_key] ||= execute.call
      end

      tool_call = RubyLLM::ToolCall.new(id: 'call_cache1', name: 'test_tool', arguments: {})

      # First call - executes the tool
      result1 = chat.send(:execute_single_tool, tool_call)
      expect(result1).to eq('original_result')

      # Second call with same args - returns cached
      tool_call2 = RubyLLM::ToolCall.new(id: 'call_cache2', name: 'test_tool', arguments: {})
      result2 = chat.send(:execute_single_tool, tool_call2)
      expect(result2).to eq('original_result')
      expect(cache.size).to eq(1) # Same cache key
    end

    it 'can implement timing/instrumentation pattern' do
      timings = []

      chat.around_tool_execution do |tool_call, _tool_instance, execute|
        start = Time.now
        result = execute.call
        elapsed = Time.now - start
        timings << { tool: tool_call.name, time: elapsed }
        result
      end

      tool_call = RubyLLM::ToolCall.new(id: 'call_time', name: 'test_tool', arguments: {})
      chat.send(:execute_single_tool, tool_call)

      expect(timings.size).to eq(1)
      expect(timings.first[:tool]).to eq('test_tool')
      expect(timings.first[:time]).to be_a(Float)
    end
  end

  describe '#around_llm_request' do
    let(:chat) { described_class.new(model: 'gpt-4o-mini') }
    let(:mock_response) do
      RubyLLM::Message.new(role: :assistant, content: 'Hello from AI')
    end
    let(:mock_provider) { instance_double(RubyLLM::Providers::OpenAI) }

    before do
      allow(mock_provider).to receive(:complete).and_return(mock_response)
      chat.instance_variable_set(:@provider, mock_provider)
    end

    it 'returns self for chaining' do
      result = chat.around_llm_request { |msgs, &send| send.call(msgs) }
      expect(result).to eq(chat)
    end

    it 'wraps LLM request with custom logic' do
      call_order = []

      chat.around_llm_request do |messages, &send_request|
        call_order << 'before'
        response = send_request.call(messages)
        call_order << 'after'
        response
      end

      chat.add_message(role: :user, content: 'Test')
      chat.complete

      expect(call_order).to eq(%w[before after])
    end

    it 'provides access to current messages' do
      received_messages = nil

      chat.around_llm_request do |messages, &send_request|
        # Snapshot messages at hook time (before response is added)
        received_messages = messages.map(&:dup)
        send_request.call(messages)
      end

      chat.add_message(role: :user, content: 'Hello')
      chat.add_message(role: :user, content: 'World')
      chat.complete

      expect(received_messages.size).to eq(2)
      expect(received_messages.first.content).to eq('Hello')
      expect(received_messages.last.content).to eq('World')
    end

    it 'allows modifying messages before sending' do
      ephemeral_message = RubyLLM::Message.new(role: :system, content: 'Ephemeral context')

      chat.around_llm_request do |messages, &send_request|
        modified = messages + [ephemeral_message]
        send_request.call(modified)
      end

      chat.add_message(role: :user, content: 'Original')
      chat.complete

      # Verify modified messages were sent to provider
      expect(mock_provider).to have_received(:complete) do |msgs, **_opts|
        expect(msgs.size).to eq(2)
        expect(msgs.last.content).to eq('Ephemeral context')
      end

      # Original messages unchanged
      expect(chat.messages.size).to eq(2) # user + assistant
      expect(chat.messages.first.content).to eq('Original')
    end

    it 'must return the response' do
      chat.around_llm_request do |messages, &send_request|
        send_request.call(messages)
        # Intentionally return a modified response
        RubyLLM::Message.new(role: :assistant, content: 'Modified response')
      end

      chat.add_message(role: :user, content: 'Test')
      response = chat.complete

      expect(response.content).to eq('Modified response')
    end

    it 'can wrap errors for retry logic' do
      attempt_count = 0

      chat.around_llm_request do |messages, &send_request|
        retries = 0
        begin
          attempt_count += 1
          raise RubyLLM::RateLimitError.new(nil, 'Rate limited') if attempt_count < 3

          send_request.call(messages)
        rescue RubyLLM::RateLimitError
          retry if (retries += 1) < 5
          raise
        end
      end

      chat.add_message(role: :user, content: 'Test')
      response = chat.complete

      expect(attempt_count).to eq(3)
      expect(response).to eq(mock_response)
    end

    it 'propagates errors when not caught' do
      chat.around_llm_request do |messages, &send_request|
        send_request.call(messages)
        raise StandardError, 'Custom error'
      end

      chat.add_message(role: :user, content: 'Test')

      expect { chat.complete }.to raise_error(StandardError, 'Custom error')
    end

    it 'works with streaming blocks' do
      chunks = []
      streaming_mock = RubyLLM::Message.new(role: :assistant, content: 'Streamed')

      allow(mock_provider).to receive(:complete) do |_msgs, **_opts, &block|
        # Simulate streaming - Chunk is a subclass of Message
        block&.call(RubyLLM::Chunk.new(role: :assistant, content: 'Hello '))
        block&.call(RubyLLM::Chunk.new(role: :assistant, content: 'World'))
        streaming_mock
      end

      hook_called = false
      chat.around_llm_request do |messages, &send_request|
        hook_called = true
        send_request.call(messages)
      end

      chat.add_message(role: :user, content: 'Stream test')
      chat.complete { |chunk| chunks << chunk.content }

      expect(hook_called).to be true
      expect(chunks).to eq(['Hello ', 'World'])
    end

    it 'works without any hook set (default behavior)' do
      chat.add_message(role: :user, content: 'Test')
      response = chat.complete

      expect(response).to eq(mock_response)
      expect(mock_provider).to have_received(:complete)
    end

    it 'replaces previous hook when called multiple times' do
      first_hook_called = false
      second_hook_called = false

      chat.around_llm_request do |messages, &send_request|
        first_hook_called = true
        send_request.call(messages)
      end

      chat.around_llm_request do |messages, &send_request|
        second_hook_called = true
        send_request.call(messages)
      end

      chat.add_message(role: :user, content: 'Test')
      chat.complete

      expect(first_hook_called).to be false
      expect(second_hook_called).to be true
    end

    it 'can implement request caching pattern' do
      cache = {}

      chat.around_llm_request do |messages, &send_request|
        cache_key = messages.map { |m| [m.role, m.content] }.hash
        cache[cache_key] ||= send_request.call(messages)
      end

      chat.add_message(role: :user, content: 'Cached request')

      # First call - executes the request
      response1 = chat.complete
      expect(response1.content).to eq('Hello from AI')

      # Reset for second request with same messages
      chat.instance_variable_get(:@messages).pop # Remove assistant message

      # Second call with same messages - returns cached
      response2 = chat.complete
      expect(response2.content).to eq('Hello from AI')

      # Provider should only be called once
      expect(mock_provider).to have_received(:complete).once
    end

    it 'can implement request timing/logging pattern' do
      timings = []

      chat.around_llm_request do |messages, &send_request|
        start = Time.now
        response = send_request.call(messages)
        elapsed = Time.now - start
        timings << { message_count: messages.size, time: elapsed }
        response
      end

      chat.add_message(role: :user, content: 'Test')
      chat.complete

      expect(timings.size).to eq(1)
      expect(timings.first[:message_count]).to eq(1)
      expect(timings.first[:time]).to be_a(Float)
    end

    it 'can implement context window management pattern' do
      chat.around_llm_request do |messages, &send_request|
        # Keep only last N messages to fit context window
        truncated = messages.last(2)
        send_request.call(truncated)
      end

      # Add many messages
      5.times { |i| chat.add_message(role: :user, content: "Message #{i}") }
      chat.complete

      # Verify only last 2 were sent
      expect(mock_provider).to have_received(:complete) do |msgs, **_opts|
        expect(msgs.size).to eq(2)
        expect(msgs.first.content).to eq('Message 3')
        expect(msgs.last.content).to eq('Message 4')
      end
    end

    it 'is thread-safe (instance-level hook)' do
      # Each chat instance has its own hook
      chat1 = described_class.new(model: 'gpt-4o-mini')
      chat2 = described_class.new(model: 'gpt-4o-mini')

      chat1.instance_variable_set(:@provider, mock_provider)
      chat2.instance_variable_set(:@provider, mock_provider)

      chat1_hook_called = false
      chat2_hook_called = false

      chat1.around_llm_request do |messages, &send_request|
        chat1_hook_called = true
        send_request.call(messages)
      end

      chat2.around_llm_request do |messages, &send_request|
        chat2_hook_called = true
        send_request.call(messages)
      end

      chat1.add_message(role: :user, content: 'Test')
      chat1.complete

      expect(chat1_hook_called).to be true
      expect(chat2_hook_called).to be false
    end
  end
end
# rubocop:enable Security/NoReflectionMethods
