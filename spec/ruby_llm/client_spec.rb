# frozen_string_literal: true

RSpec.describe RubyLLM::Client do
  let(:client) { described_class.new }
  let(:messages) { [{ role: :user, content: 'Hello!' }] }

  describe '#chat' do
    context 'with OpenAI provider' do
      before do
        RubyLLM.configure do |config|
          config.default_provider = :openai
          config.default_model = 'gpt-3.5-turbo'
        end

        stub_openai_request(
          messages: messages,
          response_content: 'Hi there!'
        )
      end

      it 'sends request to OpenAI and returns response' do
        response = client.chat(messages)
        expect(response).to be_a(RubyLLM::Message)
        expect(response.content).to eq('Hi there!')
      end
    end

    context 'with Anthropic provider' do
      before do
        RubyLLM.configure do |config|
          config.default_provider = :anthropic
          config.default_model = 'claude-3-opus-20240229'
        end

        stub_anthropic_request(
          messages: messages,
          response_content: 'Hello! How can I help you today?'
        )
      end

      it 'sends request to Anthropic and returns response' do
        response = client.chat(messages)
        expect(response).to be_a(RubyLLM::Message)
        expect(response.content).to eq('Hello! How can I help you today?')
      end
    end
  end
end
