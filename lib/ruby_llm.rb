# frozen_string_literal: true

require 'base64'
require 'event_stream_parser'
require 'faraday'
require 'faraday/multipart'
require 'faraday/retry'
require 'json'
require 'logger'
require 'marcel'
require 'securerandom'
require 'zeitwerk'
require 'async/http/faraday/default'

loader = Zeitwerk::Loader.for_gem
loader.inflector.inflect(
  'ruby_llm' => 'RubyLLM',
  'llm' => 'LLM',
  'openai' => 'OpenAI',
  'openai_responses' => 'OpenAIResponses',
  'api' => 'API',
  'deepseek' => 'DeepSeek',
  'perplexity' => 'Perplexity',
  'bedrock' => 'Bedrock',
  'openrouter' => 'OpenRouter',
  'gpustack' => 'GPUStack',
  'mistral' => 'Mistral',
  'vertexai' => 'VertexAI',
  'pdf' => 'PDF',
  'UI' => 'UI'
)
loader.ignore("#{__dir__}/tasks")
loader.ignore("#{__dir__}/generators")
loader.ignore("#{__dir__}/ruby_llm/railtie.rb")
loader.setup

# A delightful Ruby interface to modern AI language models.
module RubyLLM
  class Error < StandardError; end

  class << self
    def context
      context_config = config.dup
      yield context_config if block_given?
      Context.new(context_config)
    end

    def chat(...)
      Chat.new(...)
    end

    def embed(...)
      Embedding.embed(...)
    end

    def moderate(...)
      Moderation.moderate(...)
    end

    def paint(...)
      Image.paint(...)
    end

    def transcribe(...)
      Transcription.transcribe(...)
    end

    def models
      Models.instance
    end

    def providers
      Provider.providers.values
    end

    def configure
      yield config
    end

    def config
      @config ||= Configuration.new
    end

    def logger
      @logger ||= config.logger || Logger.new(
        config.log_file,
        progname: 'RubyLLM',
        level: config.log_level
      )
    end

    # Registry for tool execution strategies.
    # Executors receive an array of tool_calls and a block to execute each one.
    # They must return a hash mapping tool_call.id to result.
    #
    # @return [Hash{Symbol => Proc}] Map of executor names to implementations
    def tool_executors
      @tool_executors ||= {}
    end

    # Registers a new tool executor for concurrent execution.
    #
    # @param name [Symbol] Executor name (e.g., :async, :threads)
    # @yield [tool_calls, max_concurrency:, &execute] Block that executes tools concurrently
    # @yieldparam tool_calls [Array<ToolCall>] Tools to execute
    # @yieldparam max_concurrency [Integer, nil] Maximum concurrent executions
    # @yieldparam execute [Proc] Block to call for each tool
    # @yieldreturn [Hash{String => Object}] Map of tool_call.id to result
    #
    # @example
    #   RubyLLM.register_tool_executor(:custom) do |tool_calls, max_concurrency:, &execute|
    #     results = {}
    #     tool_calls.each { |tc| results[tc.id] = execute.call(tc) }
    #     results
    #   end
    def register_tool_executor(name, &block)
      tool_executors[name] = block
    end
  end
end

RubyLLM::Provider.register :anthropic, RubyLLM::Providers::Anthropic
RubyLLM::Provider.register :bedrock, RubyLLM::Providers::Bedrock
RubyLLM::Provider.register :deepseek, RubyLLM::Providers::DeepSeek
RubyLLM::Provider.register :gemini, RubyLLM::Providers::Gemini
RubyLLM::Provider.register :gpustack, RubyLLM::Providers::GPUStack
RubyLLM::Provider.register :mistral, RubyLLM::Providers::Mistral
RubyLLM::Provider.register :ollama, RubyLLM::Providers::Ollama
RubyLLM::Provider.register :openai, RubyLLM::Providers::OpenAI
RubyLLM::Provider.register :openrouter, RubyLLM::Providers::OpenRouter
RubyLLM::Provider.register :perplexity, RubyLLM::Providers::Perplexity
RubyLLM::Provider.register :vertexai, RubyLLM::Providers::VertexAI

# Load built-in tool executors for concurrent execution
require_relative 'ruby_llm/tool_executors'

if defined?(Rails::Railtie)
  require 'ruby_llm/railtie'
  require 'ruby_llm/active_record/acts_as'
end
