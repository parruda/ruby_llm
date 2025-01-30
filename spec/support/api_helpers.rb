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
          id: 'msg_' + SecureRandom.hex(12),
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
          id: 'chatcmpl-' + SecureRandom.hex(12),
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
end

RSpec.configure do |config|
  config.include ApiHelpers
end
