# frozen_string_literal: true

RSpec.describe RubyLLM::Configuration do
  let(:config) { described_class.new }

  it 'has default values' do
    expect(config.default_provider).to eq(:openai)
    expect(config.default_model).to eq('gpt-3.5-turbo')
    expect(config.request_timeout).to eq(30)
  end

  it 'allows setting API keys' do
    config.openai_api_key = 'test-key-1'
    config.anthropic_api_key = 'test-key-2'

    expect(config.openai_api_key).to eq('test-key-1')
    expect(config.anthropic_api_key).to eq('test-key-2')
  end
end
