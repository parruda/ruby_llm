# frozen_string_literal: true

module ApiHelpers
  def stub_anthropic_request(messages:, response_content:, status: 200)
    stub_request(:post, 'https://api.anthropic.com/v1/messages')
      .with(
        headers: {
          'Content-Type' => 'application/json',
          'X-Api-Key' => 'test-anthropic-key',
          'Anthropic-Version' => '2023-06-01'
        }
      ).to_return(
        status: status,
        headers: { 'Content-Type' => 'application/json' },
        body: {
          id: "msg_#{SecureRandom.hex(12)}",
          type: 'message',
          role: 'assistant',
          model: 'claude-3-opus-20240229',
          content: [
            {
              type: 'text',
              text: response_content
            }
          ],
          stop_reason: 'end_turn',
          stop_sequence: nil,
          usage: {
            input_tokens: 100,
            output_tokens: 50
          }
        }.to_json
      )
  end

  def stub_openai_request(messages:, response_content:, status: 200)
    stub_request(:post, 'https://api.openai.com/v1/chat/completions')
      .with(
        headers: {
          'Content-Type' => 'application/json',
          'Authorization' => 'Bearer test-openai-key'
        }
      ).to_return(
        status: status,
        headers: { 'Content-Type' => 'application/json' },
        body: {
          id: "chatcmpl-#{SecureRandom.hex(12)}",
          object: 'chat.completion',
          created: Time.now.to_i,
          model: 'gpt-3.5-turbo',
          choices: [
            {
              index: 0,
              message: {
                role: 'assistant',
                content: response_content
              },
              finish_reason: 'stop'
            }
          ],
          usage: {
            prompt_tokens: 100,
            completion_tokens: 50,
            total_tokens: 150
          }
        }.to_json
      )
  end

  def stub_openai_models_request
    stub_request(:get, 'https://api.openai.com/v1/models')
      .with(
        headers: {
          'Authorization' => 'Bearer test-openai-key'
        }
      ).to_return(
        status: 200,
        headers: { 'Content-Type' => 'application/json' },
        body: {
          data: [
            {
              id: 'gpt-4',
              object: 'model',
              created: Time.now.to_i,
              owned_by: 'openai'
            },
            {
              id: 'gpt-3.5-turbo',
              object: 'model',
              created: Time.now.to_i,
              owned_by: 'openai'
            }
          ]
        }.to_json
      )
  end

  def stub_anthropic_models_request
    stub_request(:get, 'https://api.anthropic.com/v1/models')
      .with(
        headers: {
          'X-Api-Key' => 'test-anthropic-key',
          'anthropic-version' => '2023-06-01'
        }
      ).to_return(
        status: 200,
        headers: { 'Content-Type' => 'application/json' },
        body: {
          data: [
            {
              type: 'model',
              id: 'claude-3-opus-20240229',
              display_name: 'Claude 3 Opus',
              created_at: '2024-02-29T00:00:00Z'
            },
            {
              type: 'model',
              id: 'claude-3-sonnet-20240229',
              display_name: 'Claude 3 Sonnet',
              created_at: '2024-02-29T00:00:00Z'
            },
            {
              type: 'model',
              id: 'claude-3-haiku-20240307',
              display_name: 'Claude 3 Haiku',
              created_at: '2024-03-07T00:00:00Z'
            },
            {
              type: 'model',
              id: 'claude-2.1',
              display_name: 'Claude 2.1',
              created_at: '2023-11-21T00:00:00Z'
            }
          ],
          has_more: false,
          first_id: 'claude-3-opus-20240229',
          last_id: 'claude-2.1'
        }.to_json
      )
  end

  def stub_models_error_request(provider)
    case provider
    when :openai
      stub_request(:get, 'https://api.openai.com/v1/models')
        .to_return(
          status: 401,
          headers: { 'Content-Type' => 'application/json' },
          body: {
            error: {
              message: 'Invalid API key',
              type: 'invalid_request_error',
              code: 'invalid_api_key'
            }
          }.to_json
        )
    when :anthropic
      stub_request(:get, 'https://api.anthropic.com/v1/models')
        .to_return(
          status: 401,
          headers: { 'Content-Type' => 'application/json' },
          body: {
            error: {
              type: 'authentication_error',
              message: 'Invalid API key'
            }
          }.to_json
        )
    end
  end
end

RSpec.configure do |config|
  config.include ApiHelpers
end
