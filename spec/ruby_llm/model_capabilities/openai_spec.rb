# frozen_string_literal: true

RSpec.describe RubyLLM::ModelCapabilities::OpenAI do
  let(:capabilities) { described_class.new }

  describe '#determine_context_window' do
    it 'returns correct context window for GPT-4' do
      expect(capabilities.determine_context_window('gpt-4-0314')).to eq(8_192)
    end

    it 'returns correct context window for GPT-4 Turbo' do
      expect(capabilities.determine_context_window('gpt-4-turbo')).to eq(128_000)
    end

    it 'returns correct context window for GPT-3.5' do
      expect(capabilities.determine_context_window('gpt-3.5-turbo')).to eq(16_385)
    end
  end

  describe '#supports_vision?' do
    it 'returns true for GPT-4o-Mini Vision' do
      expect(capabilities.supports_vision?('gpt-4-vision-preview')).to be true
    end

    it 'returns false for older models' do
      expect(capabilities.supports_vision?('gpt-4-0314')).to be false
    end
  end

  describe '#format_display_name' do
    it 'formats GPT models correctly' do
      expect(capabilities.format_display_name('gpt-4-turbo')).to eq('GPT-4-Turbo')
    end

    it 'formats version numbers correctly' do
      expect(capabilities.format_display_name('gpt-3.5-turbo')).to eq('GPT-3.5-Turbo')
    end
  end
end
