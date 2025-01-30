# frozen_string_literal: true

RSpec.describe RubyLLM::ModelInfo do
  let(:model_info) do
    described_class.new(
      id: 'test-model',
      created_at: Time.now,
      display_name: 'Test Model',
      provider: 'test',
      metadata: { version: '1.0' },
      context_window: 4096,
      max_tokens: 2048,
      supports_vision: true,
      supports_functions: true,
      supports_json_mode: true,
      input_price_per_million: 3.0,
      output_price_per_million: 6.0
    )
  end

  describe '#initialize' do
    it 'creates a valid model info object' do
      expect(model_info.id).to eq('test-model')
      expect(model_info.display_name).to eq('Test Model')
      expect(model_info.provider).to eq('test')
      expect(model_info.metadata).to eq({ version: '1.0' })
      expect(model_info.context_window).to eq(4096)
      expect(model_info.max_tokens).to eq(2048)
      expect(model_info.supports_vision).to be true
      expect(model_info.supports_functions).to be true
      expect(model_info.supports_json_mode).to be true
      expect(model_info.input_price_per_million).to eq(3.0)
      expect(model_info.output_price_per_million).to eq(6.0)
    end
  end

  describe '#to_h' do
    it 'returns a hash representation' do
      hash = model_info.to_h
      expect(hash).to be_a(Hash)
      expect(hash[:id]).to eq('test-model')
      expect(hash[:display_name]).to eq('Test Model')
      expect(hash[:provider]).to eq('test')
      expect(hash[:metadata]).to eq({ version: '1.0' })
      expect(hash[:context_window]).to eq(4096)
      expect(hash[:max_tokens]).to eq(2048)
      expect(hash[:supports_vision]).to be true
      expect(hash[:supports_functions]).to be true
      expect(hash[:supports_json_mode]).to be true
      expect(hash[:input_price_per_million]).to eq(3.0)
      expect(hash[:output_price_per_million]).to eq(6.0)
    end
  end
end
