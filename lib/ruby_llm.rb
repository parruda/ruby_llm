# frozen_string_literal: true

require 'zeitwerk'
require 'faraday'
require 'json'
require 'securerandom'
require 'logger'

# Main module for RubyLLM functionality
module RubyLLM
  class Error < StandardError; end

  class << self
    attr_writer :configuration

    def configuration
      @configuration ||= Configuration.new
    end

    def configure
      yield(configuration) if block_given?
    end

    def client
      @client ||= Client.new
    end

    def loader
      @loader ||= begin
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

        # Log autoloading in debug mode
        loader.logger = Logger.new($stdout) if ENV['RUBY_LLM_DEBUG']
        loader.enable_reloading if ENV['RUBY_LLM_DEBUG']

        loader.setup
        loader.eager_load
        loader
      end
    end
  end
end

# Initialize loader
RubyLLM.loader

# Load Rails integration if Rails is defined
if defined?(Rails)
  require 'active_support'
  require 'ruby_llm/railtie'
  require 'ruby_llm/active_record/acts_as'
end
