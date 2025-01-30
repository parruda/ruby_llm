# frozen_string_literal: true

RSpec.describe RubyLLM::Tool do
  describe '.from_method' do
    class TestClass
      def add(x, y)
        x + y
      end
    end

    let(:method_object) { TestClass.instance_method(:add) }

    it 'creates tool from method' do
      tool = described_class.from_method(
        method_object,
        description: 'Adds two numbers',
        parameter_descriptions: {
          x: 'First number',
          y: 'Second number'
        }
      )

      expect(tool.name).to eq('add')
      expect(tool.description).to eq('Adds two numbers')
      expect(tool.parameters.keys).to contain_exactly(:x, :y)
    end
  end

  describe '#call' do
    let(:tool) do
      described_class.new(
        name: 'multiply',
        description: 'Multiplies numbers',
        parameters: {
          x: { type: 'number', required: true },
          y: { type: 'number', required: true }
        }
      ) { |args| args[:x] * args[:y] }
    end

    it 'executes tool with valid arguments' do
      result = tool.call({ x: 5, y: 3 })
      expect(result).to eq(15)
    end

    it 'raises error for missing required arguments' do
      expect do
        tool.call({ x: 5 })
      end.to raise_error(ArgumentError, /Missing required parameter/)
    end
  end
end
