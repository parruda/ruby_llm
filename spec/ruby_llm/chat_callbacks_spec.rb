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
      it 'clears all messages' do
        chat.add_message(role: :user, content: 'Hello')
        chat.reset_messages!
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
end
# rubocop:enable Security/NoReflectionMethods
