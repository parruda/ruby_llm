# frozen_string_literal: true

RSpec.describe RubyLLM::Message do
  describe '#initialize' do
    it 'creates a valid message' do
      message = described_class.new(role: :user, content: 'Hello')
      expect(message.role).to eq(:user)
      expect(message.content).to eq('Hello')
    end

    it 'raises error for invalid role' do
      expect do
        described_class.new(role: :invalid, content: 'Hello')
      end.to raise_error(ArgumentError, /Invalid role/)
    end
  end

  describe '#to_h' do
    it 'returns hash representation' do
      message = described_class.new(
        role: :assistant,
        content: 'Hi there',
        tool_calls: [{ name: 'test', args: {} }]
      )

      hash = message.to_h
      expect(hash[:role]).to eq(:assistant)
      expect(hash[:content]).to eq('Hi there')
      expect(hash[:tool_calls]).to be_an(Array)
    end
  end
end
