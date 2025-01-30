# frozen_string_literal: true

RSpec.describe RubyLLM::Providers::OpenAI do
  let(:provider) { described_class.new }
  let(:messages) { [RubyLLM::Message.new(role: :user, content: 'Hello!')] }

  describe '#chat' do
    before do
      stub_openai_request(
        messages: messages,
        response_content: 'Hello! How can I assist you today?'
      )
    end

    it 'makes successful API call' do
      response = provider.chat(messages)
      expect(response.content).to eq('Hello! How can I assist you today?')
    end

    context 'with error responses' do
      before do
        stub_request(:post, 'https://api.openai.com/v1/chat/completions')
          .with(
            headers: {
              'Content-Type' => 'application/json',
              'Authorization' => 'Bearer test-openai-key'
            }
          ).to_return(
            status: 500,
            headers: { 'Content-Type' => 'application/json' },
            body: {
              error: {
                message: 'Internal server error',
                type: 'server_error',
                code: 'internal_error'
              }
            }.to_json
          )
      end

      it 'handles API errors appropriately' do
        expect { provider.chat(messages) }.to raise_error(RubyLLM::Error, 'API error: Internal server error')
      end
    end

    context 'with timeout errors' do
      before do
        allow_any_instance_of(Faraday::Connection).to receive(:post)
          .and_raise(Faraday::TimeoutError)
      end

      it 'handles timeout errors' do
        expect { provider.chat(messages) }.to raise_error(RubyLLM::Error, 'Request timed out')
      end
    end

    context 'with connection errors' do
      before do
        allow_any_instance_of(Faraday::Connection).to receive(:post)
          .and_raise(Faraday::ConnectionFailed.new('Connection failed'))
      end

      it 'handles connection errors' do
        expect { provider.chat(messages) }.to raise_error(RubyLLM::Error, 'Connection failed')
      end
    end
  end
end
