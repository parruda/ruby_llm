# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RubyLLM::Chat do
  include_context 'with configured RubyLLM'

  describe '#with_responses_api' do
    it 'returns self for chaining' do
      chat = RubyLLM.chat(model: 'gpt-4.1-nano')
      result = chat.with_responses_api

      expect(result).to be(chat)
    end

    it 'switches provider to OpenAIResponses' do
      chat = RubyLLM.chat(model: 'gpt-4.1-nano')

      expect(chat.instance_variable_get(:@provider)).to be_a(RubyLLM::Providers::OpenAI)
      expect(chat.instance_variable_get(:@provider)).not_to be_a(RubyLLM::Providers::OpenAIResponses)

      chat.with_responses_api

      expect(chat.instance_variable_get(:@provider)).to be_a(RubyLLM::Providers::OpenAIResponses)
    end

    it 'initializes a responses session' do
      chat = RubyLLM.chat(model: 'gpt-4.1-nano')

      expect(chat.responses_session).to be_nil

      chat.with_responses_api

      expect(chat.responses_session).to be_a(RubyLLM::ResponsesSession)
    end

    it 'preserves existing session when called multiple times' do
      chat = RubyLLM.chat(model: 'gpt-4.1-nano').with_responses_api
      original_session = chat.responses_session

      chat.with_responses_api(stateful: true)

      expect(chat.responses_session).to be(original_session)
    end

    it 'passes configuration to provider' do
      chat = RubyLLM.chat(model: 'gpt-4.1-nano')
        .with_responses_api(
          stateful: true,
          store: false,
          truncation: :auto,
          include: [:reasoning_encrypted_content],
          service_tier: :flex,
          max_tool_calls: 10
        )

      provider = chat.instance_variable_get(:@provider)
      expect(provider.responses_config[:stateful]).to be true
      expect(provider.responses_config[:store]).to be false
      expect(provider.responses_config[:truncation]).to eq(:auto)
      expect(provider.responses_config[:include]).to eq([:reasoning_encrypted_content])
      expect(provider.responses_config[:service_tier]).to eq(:flex)
      expect(provider.responses_config[:max_tool_calls]).to eq(10)
    end

    it 'raises ArgumentError for non-OpenAI providers' do
      chat = RubyLLM.chat(model: 'claude-3-5-haiku')

      expect {
        chat.with_responses_api
      }.to raise_error(ArgumentError, 'with_responses_api is only supported for OpenAI providers')
    end

    it 'maintains fluent API pattern' do
      chat = RubyLLM.chat(model: 'gpt-4.1-nano')
        .with_temperature(0.7)
        .with_responses_api(stateful: true)
        .with_instructions('Be helpful')

      expect(chat).to be_a(RubyLLM::Chat)
      expect(chat.responses_api_enabled?).to be true
      expect(chat.instance_variable_get(:@temperature)).to eq(0.7)
    end
  end

  describe '#responses_api_enabled?' do
    it 'returns false for standard OpenAI provider' do
      chat = RubyLLM.chat(model: 'gpt-4.1-nano')

      expect(chat.responses_api_enabled?).to be false
    end

    it 'returns true when using OpenAIResponses provider' do
      chat = RubyLLM.chat(model: 'gpt-4.1-nano').with_responses_api

      expect(chat.responses_api_enabled?).to be true
    end

    it 'returns false for other providers' do
      chat = RubyLLM.chat(model: 'claude-3-5-haiku')

      expect(chat.responses_api_enabled?).to be false
    end
  end

  describe '#restore_responses_session' do
    it 'restores session from hash' do
      time = Time.now
      session_data = {
        response_id: 'resp_123',
        last_activity: time.iso8601,
        failure_count: 1,
        disabled: false
      }

      chat = RubyLLM.chat(model: 'gpt-4.1-nano')
        .with_responses_api
        .restore_responses_session(session_data)

      expect(chat.responses_session.response_id).to eq('resp_123')
      expect(chat.responses_session.last_activity).to be_within(1).of(time)
      expect(chat.responses_session.failure_count).to eq(1)
    end

    it 'returns self for chaining' do
      session_data = { response_id: 'resp_456', last_activity: nil }
      chat = RubyLLM.chat(model: 'gpt-4.1-nano')

      result = chat.restore_responses_session(session_data)

      expect(result).to be(chat)
    end

    it 'updates provider session when already using Responses API' do
      chat = RubyLLM.chat(model: 'gpt-4.1-nano').with_responses_api

      session_data = {
        response_id: 'resp_restored',
        last_activity: Time.now.iso8601,
        failure_count: 0,
        disabled: false
      }

      chat.restore_responses_session(session_data)

      provider = chat.instance_variable_get(:@provider)
      expect(provider.responses_session.response_id).to eq('resp_restored')
    end

    it 'works before enabling Responses API' do
      session_data = {
        response_id: 'resp_early',
        last_activity: Time.now.iso8601
      }

      chat = RubyLLM.chat(model: 'gpt-4.1-nano')
        .restore_responses_session(session_data)
        .with_responses_api

      expect(chat.responses_session.response_id).to eq('resp_early')
    end
  end

  describe '#responses_session' do
    it 'is nil by default' do
      chat = RubyLLM.chat(model: 'gpt-4.1-nano')

      expect(chat.responses_session).to be_nil
    end

    it 'is accessible after enabling Responses API' do
      chat = RubyLLM.chat(model: 'gpt-4.1-nano').with_responses_api

      expect(chat.responses_session).to be_a(RubyLLM::ResponsesSession)
    end

    it 'can be serialized for persistence' do
      chat = RubyLLM.chat(model: 'gpt-4.1-nano').with_responses_api
      chat.responses_session.update('resp_persist')

      hash = chat.responses_session.to_h

      expect(hash[:response_id]).to eq('resp_persist')
      expect(hash[:last_activity]).to be_a(String)
      expect(hash[:failure_count]).to eq(0)
      expect(hash[:disabled]).to be false
    end
  end

  describe 'integration patterns' do
    it 'supports basic Responses API usage' do
      chat = RubyLLM.chat(model: 'gpt-4.1-nano')
        .with_responses_api

      expect(chat.responses_api_enabled?).to be true
      expect(chat.instance_variable_get(:@provider).completion_url).to eq('responses')
    end

    it 'supports stateful conversations' do
      chat = RubyLLM.chat(model: 'gpt-4.1-nano')
        .with_responses_api(stateful: true)

      provider = chat.instance_variable_get(:@provider)
      expect(provider.responses_config[:stateful]).to be true
    end

    it 'supports session persistence pattern' do
      # Simulate first request
      chat1 = RubyLLM.chat(model: 'gpt-4.1-nano')
        .with_responses_api(stateful: true)
      chat1.responses_session.update('resp_first')
      saved_session = chat1.responses_session.to_h

      # Simulate second request (new Chat instance)
      chat2 = RubyLLM.chat(model: 'gpt-4.1-nano')
        .with_responses_api(stateful: true)
        .restore_responses_session(saved_session)

      expect(chat2.responses_session.response_id).to eq('resp_first')
      expect(chat2.responses_session.valid?).to be true
    end

    it 'supports combined tool and temperature settings' do
      tool_class = Class.new(RubyLLM::Tool) do
        description 'Test tool'
        def name
          'test'
        end

        def execute(**)
          'result'
        end
      end

      chat = RubyLLM.chat(model: 'gpt-4.1-nano')
        .with_temperature(0.5)
        .with_tool(tool_class)
        .with_responses_api(stateful: true)
        .with_instructions('Be concise')

      expect(chat.responses_api_enabled?).to be true
      expect(chat.instance_variable_get(:@temperature)).to eq(0.5)
      expect(chat.tools).to have_key(:test)
      expect(chat.messages.last.content).to eq('Be concise')
    end
  end

  describe 'Message with Responses API attributes' do
    it 'can access response_id on Message' do
      message = RubyLLM::Message.new(
        role: :assistant,
        content: 'Hello',
        response_id: 'resp_test',
        reasoning_summary: 'Considered options',
        reasoning_tokens: 100
      )

      expect(message.response_id).to eq('resp_test')
      expect(message.reasoning_summary).to eq('Considered options')
      expect(message.reasoning_tokens).to eq(100)
    end

    it 'includes Responses API attributes in to_h' do
      message = RubyLLM::Message.new(
        role: :assistant,
        content: 'Test',
        response_id: 'resp_hash',
        reasoning_summary: 'Summary',
        reasoning_tokens: 50
      )

      hash = message.to_h

      expect(hash[:response_id]).to eq('resp_hash')
      expect(hash[:reasoning_summary]).to eq('Summary')
      expect(hash[:reasoning_tokens]).to eq(50)
    end

    it 'compacts nil Responses API attributes' do
      message = RubyLLM::Message.new(
        role: :assistant,
        content: 'Test'
      )

      hash = message.to_h

      expect(hash).not_to have_key(:response_id)
      expect(hash).not_to have_key(:reasoning_summary)
      expect(hash).not_to have_key(:reasoning_tokens)
    end
  end

  describe 'Error classes' do
    it 'defines ResponsesApiError as subclass of Error' do
      expect(RubyLLM::ResponsesApiError.superclass).to eq(RubyLLM::Error)
    end

    it 'defines specific Responses API errors' do
      expect(RubyLLM::ResponseIdNotFoundError.superclass).to eq(RubyLLM::ResponsesApiError)
      expect(RubyLLM::ResponseFailedError.superclass).to eq(RubyLLM::ResponsesApiError)
      expect(RubyLLM::ResponseInProgressError.superclass).to eq(RubyLLM::ResponsesApiError)
      expect(RubyLLM::ResponseCancelledError.superclass).to eq(RubyLLM::ResponsesApiError)
      expect(RubyLLM::ResponseIncompleteError.superclass).to eq(RubyLLM::ResponsesApiError)
    end
  end
end
