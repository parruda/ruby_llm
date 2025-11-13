# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RubyLLM::Providers::OpenAIResponses do
  include_context 'with configured RubyLLM'

  let(:config) { RubyLLM.config }
  let(:session) { RubyLLM::ResponsesSession.new }
  let(:responses_config) { { stateful: false, store: true } }
  let(:provider) { described_class.new(config, session, responses_config) }
  let(:model) { instance_double('Model', id: 'gpt-4o') }

  describe '#initialize' do
    it 'inherits from OpenAI provider' do
      expect(provider).to be_a(RubyLLM::Providers::OpenAI)
    end

    it 'sets default responses config' do
      provider = described_class.new(config)

      expect(provider.responses_config[:stateful]).to be false
      expect(provider.responses_config[:store]).to be true
      expect(provider.responses_config[:truncation]).to eq(:disabled)
      expect(provider.responses_config[:include]).to eq([])
    end

    it 'merges custom responses config' do
      custom_config = { stateful: true, store: false, truncation: :auto }
      provider = described_class.new(config, session, custom_config)

      expect(provider.responses_config[:stateful]).to be true
      expect(provider.responses_config[:store]).to be false
      expect(provider.responses_config[:truncation]).to eq(:auto)
    end

    it 'creates a default session if none provided' do
      provider = described_class.new(config)

      expect(provider.responses_session).to be_a(RubyLLM::ResponsesSession)
    end
  end

  describe '#completion_url' do
    it 'returns the responses endpoint' do
      expect(provider.completion_url).to eq('responses')
    end
  end

  describe '#render_payload' do
    let(:user_message) do
      RubyLLM::Message.new(role: :user, content: 'Hello')
    end

    let(:system_message) do
      RubyLLM::Message.new(role: :system, content: 'You are helpful')
    end

    let(:assistant_message) do
      RubyLLM::Message.new(role: :assistant, content: 'Hi there!')
    end

    describe 'basic structure' do
      it 'includes model and stream settings' do
        payload = provider.render_payload([user_message], tools: {}, temperature: nil, model: model)

        expect(payload[:model]).to eq('gpt-4o')
        expect(payload[:stream]).to be false
        expect(payload[:store]).to be true
      end

      it 'includes temperature when provided' do
        payload = provider.render_payload([user_message], tools: {}, temperature: 0.7, model: model)

        expect(payload[:temperature]).to eq(0.7)
      end

      it 'omits temperature when nil' do
        payload = provider.render_payload([user_message], tools: {}, temperature: nil, model: model)

        expect(payload).not_to have_key(:temperature)
      end

      it 'includes stream_options when streaming' do
        payload = provider.render_payload([user_message], tools: {}, temperature: nil, model: model, stream: true)

        expect(payload[:stream]).to be true
        expect(payload[:stream_options]).to eq({ include_usage: true })
      end
    end

    describe 'instructions handling' do
      it 'separates system messages into instructions' do
        payload = provider.render_payload([system_message, user_message], tools: {}, temperature: nil, model: model)

        expect(payload[:instructions]).to eq('You are helpful')
        expect(payload[:input].none? { |i| i[:role] == 'system' }).to be true
      end

      it 'joins multiple system messages' do
        system2 = RubyLLM::Message.new(role: :system, content: 'Be concise')
        messages = [system_message, system2, user_message]

        payload = provider.render_payload(messages, tools: {}, temperature: nil, model: model)

        expect(payload[:instructions]).to eq("You are helpful\n\nBe concise")
      end

      it 'omits instructions when no system messages' do
        payload = provider.render_payload([user_message], tools: {}, temperature: nil, model: model)

        expect(payload).not_to have_key(:instructions)
      end
    end

    describe 'input formatting' do
      it 'formats user messages with input_text type' do
        payload = provider.render_payload([user_message], tools: {}, temperature: nil, model: model)

        expect(payload[:input]).to eq([
                                         {
                                           type: 'message',
                                           role: 'user',
                                           content: [{ type: 'input_text', text: 'Hello' }]
                                         }
                                       ])
      end

      it 'formats assistant messages with output_text type' do
        messages = [user_message, assistant_message]
        payload = provider.render_payload(messages, tools: {}, temperature: nil, model: model)

        assistant_input = payload[:input].find { |i| i[:role] == 'assistant' }
        expect(assistant_input[:content]).to eq([{ type: 'output_text', text: 'Hi there!' }])
      end

      it 'skips empty assistant messages' do
        empty_assistant = RubyLLM::Message.new(role: :assistant, content: '')
        messages = [user_message, empty_assistant]
        payload = provider.render_payload(messages, tools: {}, temperature: nil, model: model)

        expect(payload[:input].size).to eq(1)
        expect(payload[:input].first[:role]).to eq('user')
      end

      it 'formats tool results as function_call_output' do
        tool_result = RubyLLM::Message.new(role: :tool, content: '{"result": 42}', tool_call_id: 'call_123')
        messages = [user_message, tool_result]

        payload = provider.render_payload(messages, tools: {}, temperature: nil, model: model)

        expect(payload[:input].last).to eq({
                                              type: 'function_call_output',
                                              call_id: 'call_123',
                                              output: '{"result": 42}'
                                            })
      end
    end

    describe 'stateful mode' do
      let(:stateful_provider) do
        config = { stateful: true, store: true }
        session = RubyLLM::ResponsesSession.new
        session.update('resp_previous')
        described_class.new(RubyLLM.config, session, config)
      end

      it 'includes previous_response_id when valid session' do
        payload = stateful_provider.render_payload([user_message], tools: {}, temperature: nil, model: model)

        expect(payload[:previous_response_id]).to eq('resp_previous')
      end

      it 'sends only new input after last assistant message' do
        messages = [
          user_message,
          assistant_message,
          RubyLLM::Message.new(role: :user, content: 'Follow up')
        ]

        payload = stateful_provider.render_payload(messages, tools: {}, temperature: nil, model: model)

        expect(payload[:input].size).to eq(1)
        expect(payload[:input].first[:content].first[:text]).to eq('Follow up')
      end

      it 'sends tool results and new user messages in stateful mode' do
        tool_result = RubyLLM::Message.new(role: :tool, content: 'result', tool_call_id: 'call_1')
        new_user = RubyLLM::Message.new(role: :user, content: 'Thanks')
        messages = [user_message, assistant_message, tool_result, new_user]

        payload = stateful_provider.render_payload(messages, tools: {}, temperature: nil, model: model)

        expect(payload[:input].size).to eq(2)
        expect(payload[:input][0][:type]).to eq('function_call_output')
        expect(payload[:input][1][:type]).to eq('message')
      end

      it 'falls back to full history when session is invalid' do
        invalid_session = RubyLLM::ResponsesSession.new # No response_id
        invalid_provider = described_class.new(
          RubyLLM.config,
          invalid_session,
          { stateful: true, store: true }
        )

        messages = [user_message, assistant_message, RubyLLM::Message.new(role: :user, content: 'New')]
        payload = invalid_provider.render_payload(messages, tools: {}, temperature: nil, model: model)

        expect(payload).not_to have_key(:previous_response_id)
        expect(payload[:input].size).to eq(3)
      end
    end

    describe 'schema formatting' do
      it 'includes text format for structured output' do
        schema = { type: 'object', properties: { name: { type: 'string' } } }
        payload = provider.render_payload([user_message], tools: {}, temperature: nil, model: model, schema: schema)

        expect(payload[:text]).to eq({
                                       format: {
                                         type: 'json_schema',
                                         name: 'response',
                                         schema: schema,
                                         strict: true
                                       }
                                     })
      end

      it 'respects strict: false in schema' do
        schema = { type: 'object', strict: false }
        payload = provider.render_payload([user_message], tools: {}, temperature: nil, model: model, schema: schema)

        expect(payload[:text][:format][:strict]).to be false
      end
    end

    describe 'optional parameters' do
      it 'includes truncation when not disabled' do
        config = { stateful: false, store: true, truncation: :auto }
        provider = described_class.new(RubyLLM.config, session, config)

        payload = provider.render_payload([user_message], tools: {}, temperature: nil, model: model)

        expect(payload[:truncation]).to eq('auto')
      end

      it 'excludes truncation when disabled' do
        payload = provider.render_payload([user_message], tools: {}, temperature: nil, model: model)

        expect(payload).not_to have_key(:truncation)
      end

      it 'includes include array with proper formatting' do
        config = { stateful: false, store: true, include: [:reasoning_encrypted_content] }
        provider = described_class.new(RubyLLM.config, session, config)

        payload = provider.render_payload([user_message], tools: {}, temperature: nil, model: model)

        expect(payload[:include]).to eq(['reasoning.encrypted.content'])
      end

      it 'includes service_tier when provided' do
        config = { stateful: false, store: true, service_tier: :flex }
        provider = described_class.new(RubyLLM.config, session, config)

        payload = provider.render_payload([user_message], tools: {}, temperature: nil, model: model)

        expect(payload[:service_tier]).to eq('flex')
      end

      it 'includes max_tool_calls when provided' do
        config = { stateful: false, store: true, max_tool_calls: 10 }
        provider = described_class.new(RubyLLM.config, session, config)

        payload = provider.render_payload([user_message], tools: {}, temperature: nil, model: model)

        expect(payload[:max_tool_calls]).to eq(10)
      end
    end
  end

  describe '#tool_for' do
    let(:tool_class) do
      Class.new(RubyLLM::Tool) do
        description 'Get the current weather'
        param :location, type: 'string', desc: 'City name'

        def name
          'get_weather'
        end

        def execute(location:)
          "Weather in #{location}: Sunny"
        end
      end
    end

    let(:tool) { tool_class.new }

    it 'uses flat format without nested function key' do
      result = provider.tool_for(tool)

      expect(result[:type]).to eq('function')
      expect(result[:name]).to eq('get_weather')
      expect(result[:description]).to eq('Get the current weather')
      expect(result[:parameters]).to be_a(Hash)
      # Should NOT have nested :function key
      expect(result).not_to have_key(:function)
    end

    it 'includes parameters schema' do
      result = provider.tool_for(tool)

      expect(result[:parameters]['type']).to eq('object')
      expect(result[:parameters]['properties']).to have_key('location')
    end

    it 'merges provider_params' do
      tool_with_params_class = Class.new(RubyLLM::Tool) do
        description 'Test tool'
        with_params strict: true

        def name
          'test_tool'
        end

        def execute(**)
          'result'
        end
      end

      tool_with_params = tool_with_params_class.new
      result = provider.tool_for(tool_with_params)

      expect(result[:strict]).to be true
    end
  end

  describe '#parse_completion_response' do
    let(:basic_response_body) do
      {
        'id' => 'resp_123',
        'status' => 'completed',
        'model' => 'gpt-4o',
        'output' => [
          {
            'type' => 'message',
            'content' => [
              { 'type' => 'output_text', 'text' => 'Hello!' }
            ]
          }
        ],
        'usage' => {
          'input_tokens' => 10,
          'output_tokens' => 5,
          'output_tokens_details' => { 'reasoning_tokens' => 2 }
        },
        'reasoning' => {
          'summary' => 'Considered greeting options'
        }
      }
    end

    it 'parses completed response' do
      response = instance_double(Faraday::Response, body: basic_response_body)

      message = provider.parse_completion_response(response)

      expect(message.content).to eq('Hello!')
      expect(message.role).to eq(:assistant)
      expect(message.model_id).to eq('gpt-4o')
    end

    it 'extracts response_id' do
      response = instance_double(Faraday::Response, body: basic_response_body)

      message = provider.parse_completion_response(response)

      expect(message.response_id).to eq('resp_123')
    end

    it 'extracts reasoning metadata' do
      response = instance_double(Faraday::Response, body: basic_response_body)

      message = provider.parse_completion_response(response)

      expect(message.reasoning_summary).to eq('Considered greeting options')
      expect(message.reasoning_tokens).to eq(2)
    end

    it 'extracts usage information' do
      response = instance_double(Faraday::Response, body: basic_response_body)

      message = provider.parse_completion_response(response)

      expect(message.input_tokens).to eq(10)
      expect(message.output_tokens).to eq(5)
      expect(message.cache_creation_tokens).to eq(0)
    end

    it 'handles missing reasoning' do
      body = basic_response_body.dup
      body.delete('reasoning')
      response = instance_double(Faraday::Response, body: body)

      message = provider.parse_completion_response(response)

      expect(message.reasoning_summary).to be_nil
    end

    it 'parses tool calls' do
      body = basic_response_body.merge(
        'output' => [
          {
            'type' => 'function_call',
            'call_id' => 'call_abc',
            'name' => 'get_weather',
            'arguments' => '{"location": "NYC"}'
          }
        ]
      )
      response = instance_double(Faraday::Response, body: body)

      message = provider.parse_completion_response(response)

      expect(message.tool_calls).to have_key('call_abc')
      expect(message.tool_calls['call_abc'].name).to eq('get_weather')
      expect(message.tool_calls['call_abc'].arguments).to eq({ 'location' => 'NYC' })
    end

    it 'handles tool calls with hash arguments' do
      body = basic_response_body.merge(
        'output' => [
          {
            'type' => 'function_call',
            'call_id' => 'call_xyz',
            'name' => 'test',
            'arguments' => { 'key' => 'value' }
          }
        ]
      )
      response = instance_double(Faraday::Response, body: body)

      message = provider.parse_completion_response(response)

      expect(message.tool_calls['call_xyz'].arguments).to eq({ 'key' => 'value' })
    end

    it 'handles empty tool call arguments' do
      body = basic_response_body.merge(
        'output' => [
          {
            'type' => 'function_call',
            'call_id' => 'call_empty',
            'name' => 'test',
            'arguments' => ''
          }
        ]
      )
      response = instance_double(Faraday::Response, body: body)

      message = provider.parse_completion_response(response)

      expect(message.tool_calls['call_empty'].arguments).to eq({})
    end

    it 'raises ResponseFailedError on failed status' do
      body = {
        'id' => 'resp_fail',
        'status' => 'failed',
        'error' => { 'message' => 'Something went wrong' }
      }
      response = instance_double(Faraday::Response, body: body)

      expect {
        provider.parse_completion_response(response)
      }.to raise_error(RubyLLM::ResponseFailedError, 'Something went wrong')
    end

    it 'raises ResponseInProgressError on in_progress status' do
      body = {
        'id' => 'resp_prog',
        'status' => 'in_progress'
      }
      response = instance_double(Faraday::Response, body: body)

      expect {
        provider.parse_completion_response(response)
      }.to raise_error(RubyLLM::ResponseInProgressError)
    end

    it 'raises ResponseCancelledError on cancelled status' do
      body = {
        'id' => 'resp_cancel',
        'status' => 'cancelled'
      }
      response = instance_double(Faraday::Response, body: body)

      expect {
        provider.parse_completion_response(response)
      }.to raise_error(RubyLLM::ResponseCancelledError)
    end

    it 'handles incomplete status with warning' do
      body = basic_response_body.merge(
        'status' => 'incomplete',
        'incomplete_details' => { 'reason' => 'max_output_tokens' }
      )
      response = instance_double(Faraday::Response, body: body)

      expect(RubyLLM.logger).to receive(:warn).with(/Incomplete response/)

      message = provider.parse_completion_response(response)

      expect(message.content).to eq('Hello!')
    end

    it 'handles nil body' do
      response = instance_double(Faraday::Response, body: nil)

      result = provider.parse_completion_response(response)

      expect(result).to be_nil
    end

    it 'handles empty body' do
      response = instance_double(Faraday::Response, body: {})

      result = provider.parse_completion_response(response)

      expect(result).to be_nil
    end

    it 'raises on error in response' do
      body = { 'error' => { 'message' => 'API error' } }
      response = instance_double(Faraday::Response, body: body)

      expect {
        provider.parse_completion_response(response)
      }.to raise_error(RubyLLM::Error, 'API error')
    end
  end

  describe '#build_chunk' do
    it 'handles response.content_part.delta events' do
      data = {
        'type' => 'response.content_part.delta',
        'delta' => { 'text' => 'Hello' }
      }

      chunk = provider.build_chunk(data)

      expect(chunk.content).to eq('Hello')
      expect(chunk.role).to eq(:assistant)
    end

    it 'handles response.completed events' do
      data = {
        'type' => 'response.completed',
        'response' => {
          'model' => 'gpt-4o',
          'usage' => {
            'input_tokens' => 10,
            'output_tokens' => 20
          }
        }
      }

      chunk = provider.build_chunk(data)

      expect(chunk.model_id).to eq('gpt-4o')
      expect(chunk.input_tokens).to eq(10)
      expect(chunk.output_tokens).to eq(20)
    end

    it 'handles other response events' do
      data = {
        'type' => 'response.created'
      }

      chunk = provider.build_chunk(data)

      expect(chunk.content).to be_nil
      expect(chunk.role).to eq(:assistant)
    end

    it 'falls back to parent for non-responses-api events' do
      data = {
        'model' => 'gpt-4o',
        'choices' => [{ 'delta' => { 'content' => 'Hi' } }]
      }

      expect(provider).to receive(:parse_tool_calls).and_return(nil)

      chunk = provider.build_chunk(data)

      expect(chunk.content).to eq('Hi')
    end
  end

  describe 'error recovery' do
    it 'retries when response ID not found' do
      # This test would require VCR cassettes for full integration testing
      # Here we test the detection logic
      error = RubyLLM::BadRequestError.new(nil, 'Previous response ID not found')

      expect(provider.send(:response_id_not_found_error?, error)).to be false

      session.update('resp_123')
      expect(provider.send(:response_id_not_found_error?, error)).to be true
    end

    it 'records failure when response ID not found' do
      session.update('resp_123')

      provider.send(:handle_response_id_failure)

      expect(session.response_id).to be_nil
      expect(session.failure_count).to eq(1)
    end

    it 'disables stateful mode after max failures' do
      session.update('resp_123')

      RubyLLM::ResponsesSession::MAX_FAILURES.times do
        provider.send(:handle_response_id_failure)
      end

      expect(session.disabled?).to be true
    end
  end
end
