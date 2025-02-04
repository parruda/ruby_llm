# frozen_string_literal: true

require 'zeitwerk'
require 'faraday'
require 'json'
require 'logger'
require 'event_stream_parser'
require 'securerandom'

# A delightful Ruby interface to modern AI language models.
# Provides a unified way to interact with models from OpenAI, Anthropic and others
# with a focus on developer happiness and convention over configuration.
module RubyLLM
  class Error < StandardError; end

  class << self
    def chat(model: nil)
      Chat.new(model: model)
    end

    def models
      Models
    end

    def configure
      yield config
    end

    def config
      @config ||= Configuration.new
    end

    def logger
      @logger ||= Logger.new(
        $stdout,
        progname: 'RubyLLM',
        level: ENV['RUBY_LLM_DEBUG'] == 'true' ? Logger::DEBUG : Logger::INFO
      )
    end
  end
end

loader = Zeitwerk::Loader.for_gem

# Add lib directory to the load path
loader.push_dir(File.expand_path('..', __dir__))

# Configure custom inflections
loader.inflector.inflect(
  'ruby_llm' => 'RubyLLM',
  'llm' => 'LLM',
  'openai' => 'OpenAI',
  'api' => 'API'
)

# Ignore Rails-specific files and specs
loader.ignore("#{__dir__}/ruby_llm/railtie.rb")
loader.ignore("#{__dir__}/ruby_llm/active_record")
loader.ignore(File.expand_path('../spec', __dir__).to_s)

loader.enable_reloading if ENV['RUBY_LLM_DEBUG']

loader.setup
loader.eager_load if ENV['RUBY_LLM_DEBUG']

RubyLLM::Provider.register :openai, RubyLLM::Providers::OpenAI
RubyLLM::Provider.register :anthropic, RubyLLM::Providers::Anthropic

# Load Rails integration if Rails is defined
if defined?(Rails)
  require 'ruby_llm/railtie'
  require 'ruby_llm/active_record/acts_as'
end
