# frozen_string_literal: true

require 'spec_helper'
require 'dotenv/load'

RSpec.describe RubyLLM::Chat do
  include_context 'with configured RubyLLM'

  class Calculator < RubyLLM::Tool # rubocop:disable Lint/ConstantDefinitionInBlock,RSpec/LeakyConstantDeclaration
    description 'Performs basic arithmetic'

    param :expression,
          type: :string,
          desc: 'Math expression to evaluate'

    def execute(expression:)
      eval(expression).to_s # rubocop:disable Security/Eval
    rescue StandardError => e
      "Error: #{e.message}"
    end
  end

  describe 'function calling' do
    [
      'claude-3-5-haiku-20241022',
      'gemini-2.0-flash',
      'gpt-4o-mini'
    ].each do |model|
      it "#{model} can use tools" do
        chat = RubyLLM.chat(model: model)
                      .with_tool(Calculator)

        response = chat.ask("What's 123 * 456?")
        expect(response.content).to include(/56(,?)088/)
      end

      it 'can use tools in multi-turn conversations' do # rubocop:disable RSpec/ExampleLength,RSpec/MultipleExpectations
        chat = RubyLLM.chat(model: model)
                      .with_tool(Calculator)

        response = chat.ask("What's 123 times 456?")
        expect(response.content).to include(/56(,?)088/)

        response = chat.ask("What's 456 divided by 123?")
        expect(response.content).to include('3')
      end

      it "#{model} can use tools with multi-turn streaming conversations" do # rubocop:disable RSpec/ExampleLength,RSpec/MultipleExpectations
        chat = RubyLLM.chat(model: model)
                      .with_tool(Calculator)
        chunks = []

        response = chat.ask("What's 123 * 456?") do |chunk|
          chunks << chunk
        end

        expect(chunks).not_to be_empty
        expect(chunks.first).to be_a(RubyLLM::Chunk)
        expect(response.content).to include(/56(,?)088/)

        response = chat.ask("What's 456 divided by 123?") do |chunk|
          chunks << chunk
        end

        expect(chunks).not_to be_empty
        expect(chunks.first).to be_a(RubyLLM::Chunk)
        expect(response.content).to include('3')
      end
    end
  end
end
