# frozen_string_literal: true

require 'spec_helper'
require 'dotenv/load'

RSpec.describe 'Chat Integration' do # rubocop:disable Metrics/BlockLength
  before(:all) do
    RubyLLM.configure do |config|
      config.openai_api_key = ENV.fetch('OPENAI_API_KEY')
      config.anthropic_api_key = ENV.fetch('ANTHROPIC_API_KEY')
      config.gemini_api_key = ENV.fetch('GEMINI_API_KEY')
      config.max_retries = 10
    end
  end

  describe 'basic chat functionality' do
    [
      'claude-3-5-sonnet-20241022',
      'gemini-2.0-flash',
      'gpt-4o-mini'
    ].each do |model|
      context "with #{model}" do
        it 'can have a basic conversation' do
          chat = RubyLLM.chat(model: model)
          response = chat.ask("What's 2 + 2?")

          expect(response.content).to include('4')
          expect(response.role).to eq(:assistant)
          expect(response.input_tokens).to be_positive
          expect(response.output_tokens).to be_positive
        end

        it 'can handle multi-turn conversations' do
          chat = RubyLLM.chat(model: model)

          first = chat.ask("Who was Ruby's creator?")
          expect(first.content).to include('Matz')

          followup = chat.ask('What year did he create Ruby?')
          expect(followup.content).to include('199')
        end
      end
    end
  end
end
