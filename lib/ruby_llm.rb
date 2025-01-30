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
    attr_accessor :configuration

    def configure
      self.configuration ||= Configuration.new
      yield(configuration) if block_given?
    end

    def client
      @client ||= Client.new
    end

    def loader
      @loader ||= begin
        loader = Zeitwerk::Loader.for_gem
        loader.push_dir(File.expand_path('..', __dir__))
        loader.inflector.inflect(
          'llm' => 'LLM',
          'openai' => 'OpenAI',
          'api' => 'API'
        )

        # Log the paths being loaded in development
        loader.logger = Logger.new($stdout) if ENV['RUBY_LLM_DEBUG']

        loader.setup
        loader
      end
    end
  end
end

# Setup Zeitwerk loader first
RubyLLM.loader

# Then require core files explicitly
require_relative 'ruby_llm/configuration'
require_relative 'ruby_llm/message'
require_relative 'ruby_llm/tool'
require_relative 'ruby_llm/providers/base'
require_relative 'ruby_llm/client'
require_relative 'ruby_llm/conversation'

# Load providers
require_relative 'ruby_llm/providers/openai'
require_relative 'ruby_llm/providers/anthropic'
