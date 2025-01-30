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

    it 'makes successful API call and returns array' do
      response = provider.chat(messages)
      expect(response).to be_an(Array)
      expect(response.first.content).to eq('Hello! How can I assist you today?')
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
  end
end
