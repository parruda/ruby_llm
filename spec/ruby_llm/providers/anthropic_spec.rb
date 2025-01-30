# frozen_string_literal: true

RSpec.describe RubyLLM::Providers::Anthropic do
  let(:provider) { described_class.new }
  let(:messages) { [RubyLLM::Message.new(role: :user, content: 'What time is it?')] }

  describe '#chat' do
    context 'with tools' do
      let(:tool) do
        RubyLLM::Tool.new(
          name: 'get_time',
          description: 'Get the current time',
          parameters: {}
        ) { Time.now.to_s }
      end

      let(:tool_response) { '2025-01-30 13:54:47 +0100' }

      it 'returns array with all messages' do
        response = provider.chat(messages, tools: [tool])
        expect(response).to be_an(Array)
        expect(response.length).to eq(3)

        # Check tool call message
        expect(response[0]).to be_a(RubyLLM::Message)
        expect(response[0].tool_calls).to be_an(Array)
        expect(response[0].tool_calls.first[:name]).to eq('get_time')

        # Check tool result message
        expect(response[1]).to be_a(RubyLLM::Message)
        expect(response[1].content).to eq(tool_response)

        # Check final response
        expect(response[2]).to be_a(RubyLLM::Message)
        expect(response[2].content).to eq("The current time is #{tool_response}.")
      end

      it 'yields messages in sequence when block given' do
        messages_received = []
        response = provider.chat(messages, tools: [tool]) do |message|
          messages_received << message
        end

        expect(messages_received.length).to eq(3)
        expect(messages_received.map(&:role)).to eq(%i[assistant tool assistant])
        expect(response).to eq(messages_received)
      end
    end
  end
end
