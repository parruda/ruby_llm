# frozen_string_literal: true

require 'spec_helper'
require 'dotenv/load'

RSpec.describe RubyLLM::Chat do
  before(:all) do # rubocop:disable RSpec/BeforeAfterAll
    RubyLLM.configure do |config|
      config.openai_api_key = ENV.fetch('OPENAI_API_KEY')
      config.anthropic_api_key = ENV.fetch('ANTHROPIC_API_KEY')
      config.deepseek_api_key = ENV.fetch('DEEPSEEK_API_KEY')
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

  describe 'streaming responses' do
    [
      'claude-3-5-haiku-20241022',
      'gemini-2.0-flash',
      'deepseek-chat',
      'gpt-4o-mini'
    ].each do |model|
      context "with #{model}" do
        it 'supports streaming responses' do # rubocop:disable RSpec/ExampleLength,RSpec/MultipleExpectations
          chat = RubyLLM.chat(model: model)
          chunks = []

          chat.ask('Count from 1 to 3') do |chunk|
            chunks << chunk
          end

          expect(chunks).not_to be_empty
          expect(chunks.first).to be_a(RubyLLM::Chunk)
        end
      end
    end
  end
end
