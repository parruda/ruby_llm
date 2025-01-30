# frozen_string_literal: true

RSpec.describe RubyLLM::ModelCapabilities::Anthropic do
  let(:capabilities) { described_class.new }

  describe '#determine_context_window' do
    it 'returns correct context window for Claude 3' do
      expect(capabilities.determine_context_window('claude-3-opus')).to eq(200_000)
    end

    it 'returns correct context window for older models' do
      expect(capabilities.determine_context_window('claude-2.1')).to eq(100_000)
    end
  end

  describe '#supports_vision?' do
    it 'returns true for Claude 3 Opus' do
      expect(capabilities.supports_vision?('claude-3-opus')).to be true
    end

    it 'returns false for Claude 3.5 Haiku' do
      expect(capabilities.supports_vision?('claude-3-5-haiku')).to be false
    end
  end

  describe '#get_input_price' do
    it 'returns correct price for Claude 3 Opus' do
      expect(capabilities.get_input_price('claude-3-opus')).to eq(15.0)
    end

    it 'returns correct price for Claude 3 Haiku' do
      expect(capabilities.get_input_price('claude-3-haiku')).to eq(0.25)
    end
  end
end
