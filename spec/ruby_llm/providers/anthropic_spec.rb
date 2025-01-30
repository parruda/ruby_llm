# frozen_string_literal: true

RSpec.describe RubyLLM::Providers::Anthropic do
  let(:provider) { described_class.new }
  let(:messages) { [RubyLLM::Message.new(role: :user, content: 'What time is it?')] }

  describe '#chat' do
    before do
      stub_anthropic_request(
        messages: messages,
        response_content: 'Hi there!'
      )
    end

    it 'makes successful API call' do
      response = provider.chat(messages)
      expect(response.content).to eq('Hi there!')
    end

    context 'with tools' do
      let(:tool) do
        RubyLLM::Tool.new(
          name: 'get_time',
          description: 'Get the current time',
          parameters: {}
        ) { Time.now.to_s }
      end

      let(:tool_response) { '2025-01-30 13:54:47 +0100' }

      before do
        # First request - Claude decides to use the tool
        stub_request(:post, 'https://api.anthropic.com/v1/messages')
          .with(
            headers: {
              'Content-Type' => 'application/json',
              'X-Api-Key' => 'test-anthropic-key',
              'Anthropic-Version' => '2023-06-01'
            }
          ).to_return(
            status: 200,
            headers: { 'Content-Type' => 'application/json' },
            body: {
              id: 'msg_01UAcKZjQCESKUi9thQQRGvp',
              type: 'message',
              role: 'assistant',
              model: 'claude-3-opus-20240229',
              content: [
                {
                  type: 'text',
                  text: 'Let me check the current time.'
                },
                {
                  type: 'tool_use',
                  id: 'toolu_01DYRxKRbA1qRgFiSX1aTMiM',
                  name: 'get_time',
                  input: {}
                }
              ],
              stop_reason: 'tool_use',
              usage: {
                input_tokens: 587,
                output_tokens: 73
              }
            }.to_json
          ).then
          # Second request - Final response after tool execution
          .to_return(
            status: 200,
            headers: { 'Content-Type' => 'application/json' },
            body: {
              id: 'msg_01K59k1tvTpA2DwcWEB3u3ND',
              type: 'message',
              role: 'assistant',
              model: 'claude-3-opus-20240229',
              content: [
                {
                  type: 'text',
                  text: "The current time is #{tool_response}."
                }
              ],
              stop_reason: 'end_turn',
              usage: {
                input_tokens: 687,
                output_tokens: 26
              }
            }.to_json
          )

        allow(Time).to receive(:now).and_return(Time.parse('2025-01-30 13:54:47 +0100'))
      end

      it 'handles tool calls' do
        response = provider.chat(messages, tools: [tool])
        expect(response.content).to eq("The current time is #{tool_response}.")
      end
    end
  end
end
