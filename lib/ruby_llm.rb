# frozen_string_literal: true

require 'zeitwerk'
require 'faraday'
require 'json'

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
        loader.inflector.inflect(
          'llm' => 'LLM',
          'openai' => 'OpenAI',
          'api' => 'API'
        )
        loader.setup
        loader
      end
    end
  end
end

RubyLLM.loader
