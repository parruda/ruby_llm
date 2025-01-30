# frozen_string_literal: true

require 'simplecov'
SimpleCov.start do
  add_filter '/spec/'
end

require 'bundler/setup'
require 'dotenv/load'
require 'ruby_llm'
require 'webmock/rspec'
require 'time'

Dir[File.join(__dir__, 'support', '**', '*.rb')].sort.each { |f| require f }

RSpec.configure do |config|
  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end

  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end

  config.shared_context_metadata_behavior = :apply_to_host_groups
  config.filter_run_when_matching :focus
  config.example_status_persistence_file_path = 'spec/examples.txt'
  config.disable_monkey_patching!
  config.warnings = true

  config.before(:each) do
    RubyLLM.configuration = RubyLLM::Configuration.new
    RubyLLM.configuration.openai_api_key = 'test-openai-key'
    RubyLLM.configuration.anthropic_api_key = 'test-anthropic-key'
  end
end

# Disable all real network connections
WebMock.disable_net_connect!(allow_localhost: true)
