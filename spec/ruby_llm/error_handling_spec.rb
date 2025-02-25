# frozen_string_literal: true

require 'spec_helper'
require 'dotenv/load'

RSpec.describe RubyLLM::Error do
  it 'handles invalid API keys gracefully' do # rubocop:disable RSpec/ExampleLength
    RubyLLM.configure do |config|
      config.anthropic_api_key = 'invalid-key'
    end

    chat = RubyLLM.chat(model: 'claude-3-5-haiku-20241022')

    expect do
      chat.ask('Hello')
    end.to raise_error(RubyLLM::UnauthorizedError)
  end
end
