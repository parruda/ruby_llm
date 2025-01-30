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

      it 'sends request to OpenAI and returns array of responses' do
        response = client.chat(messages)
        expect(response).to be_an(Array)
        expect(response.first).to be_a(RubyLLM::Message)
        expect(response.first.content).to eq('Hi there!')
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

      it 'sends request to Anthropic and returns array of responses' do
        response = client.chat(messages)
        expect(response).to be_an(Array)
        expect(response.first).to be_a(RubyLLM::Message)
        expect(response.first.content).to eq('Hello! How can I help you today?')
      end
    end
  end

  describe '#list_models' do
    context 'with successful responses' do
      before do
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
                  id: 'gpt-4o-mini',
                  object: 'model',
                  created: Time.now.to_i,
                  owned_by: 'openai'
                }
              ]
            }.to_json
          )

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
                  id: 'claude-2.1',
                  display_name: 'Claude 2.1',
                  created_at: '2023-11-21T00:00:00Z'
                }
              ]
            }.to_json
          )
      end

      it 'returns models from all providers when no provider specified' do
        models = client.list_models
        expect(models).not_to be_empty
        expect(models.map(&:provider).uniq.sort).to eq(%w[anthropic openai])
      end

      it 'returns only OpenAI models when specified' do
        models = client.list_models(:openai)
        expect(models).not_to be_empty
        expect(models.map(&:provider).uniq).to eq(['openai'])

        gpt4_model = models.find { |m| m.id == 'gpt-4' }
        expect(gpt4_model).to have_attributes(
          provider: 'openai',
          supports_vision: false,          # GPT-4 base doesn't support vision
          supports_functions: true,        # All non-instruct models support functions
          supports_json_mode: false        # Base GPT-4 doesn't support JSON mode
        )

        gpt4o_mini = models.find { |m| m.id == 'gpt-4o-mini' }
        expect(gpt4o_mini).to have_attributes(
          provider: 'openai',
          supports_vision: false,          # gpt-4o-mini doesn't support vision
          supports_functions: true,        # Supports functions
          supports_json_mode: false        # Doesn't support JSON mode
        )
      end

      it 'returns only Anthropic models when specified' do
        models = client.list_models(:anthropic)
        expect(models).not_to be_empty
        expect(models.map(&:provider).uniq).to eq(['anthropic'])

        opus_model = models.find { |m| m.id == 'claude-3-opus-20240229' }
        expect(opus_model).to have_attributes(
          provider: 'anthropic',
          supports_vision: true,          # Claude 3 Opus supports vision
          supports_functions: true,       # Claude 3 supports functions
          supports_json_mode: true        # Claude 3 supports JSON mode
        )

        claude2_model = models.find { |m| m.id == 'claude-2.1' }
        expect(claude2_model).to have_attributes(
          provider: 'anthropic',
          supports_vision: false,         # Claude 2 doesn't support vision
          supports_functions: false,      # Claude 2 doesn't support functions
          supports_json_mode: false       # Claude 2 doesn't support JSON mode
        )
      end
    end

    context 'with error responses' do
      it 'handles OpenAI API errors' do
        stub_request(:get, 'https://api.openai.com/v1/models')
          .to_return(
            status: 401,
            headers: { 'Content-Type' => 'application/json' },
            body: {
              error: {
                message: 'Invalid API key'
              }
            }.to_json
          )

        expect { client.list_models(:openai) }
          .to raise_error(RubyLLM::Error, /API error: Invalid API key/)
      end

      it 'handles Anthropic API errors' do
        stub_request(:get, 'https://api.anthropic.com/v1/models')
          .to_return(
            status: 401,
            headers: { 'Content-Type' => 'application/json' },
            body: {
              error: {
                message: 'Invalid API key'
              }
            }.to_json
          )

        expect { client.list_models(:anthropic) }
          .to raise_error(RubyLLM::Error, /API error: Invalid API key/)
      end

      it 'handles invalid provider specification' do
        expect { client.list_models(:invalid_provider) }
          .to raise_error(RubyLLM::Error, /Unsupported provider/)
      end
    end
  end
end
