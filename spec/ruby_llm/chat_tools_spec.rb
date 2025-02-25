# frozen_string_literal: true

require 'spec_helper'
require 'dotenv/load'

RSpec.describe RubyLLM::Chat do
  before(:all) do # rubocop:disable RSpec/BeforeAfterAll
    RubyLLM.configure do |config|
      config.openai_api_key = ENV.fetch('OPENAI_API_KEY')
      config.anthropic_api_key = ENV.fetch('ANTHROPIC_API_KEY')
      config.gemini_api_key = ENV.fetch('GEMINI_API_KEY')
    end
  end

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
      'claude-3-5-sonnet-20241022',
      'gemini-2.0-flash',
      'gpt-4o-mini'
    ].each do |model|
      context "with #{model}" do
        it 'can use tools' do
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
      end
    end
  end
end
