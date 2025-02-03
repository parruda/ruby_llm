# frozen_string_literal: true

module RubyLLM
  class Chat
    include Enumerable

    attr_reader :model, :messages, :tools

    def initialize(model: nil)
      model_id = model || RubyLLM.config.default_model
      @model = Models.find model_id
      @provider = Models.provider_for model_id
      @messages = []
      @tools = {}

      ensure_valid_tools
    end

    def ask(message, &block)
      add_message role: :user, content: message
      complete(&block)
    end

    alias say ask

    def with_tool(tool)
      raise Error, "Model #{@model.id} doesn't support function calling" unless @model.supports_functions

      @tools[tool.name] = tool
      self
    end

    def with_tools(*tools)
      tools.each { |tool| with_tool tool }
      self
    end

    def each(&block)
      messages.each(&block)
    end

    private

    def complete(&block)
      response = @provider.complete(messages, tools: @tools, model: @model.id, &block)

      if response.tool_call?
        handle_tool_calls response, &block
      else
        add_message response
        response
      end
    end

    def handle_tool_calls(response, &block)
      add_message response

      response.tool_calls.each_value do |tool_call|
        result = execute_tool tool_call
        add_tool_result tool_call.id, result if result
      end

      complete(&block)
    end

    def execute_tool(tool_call)
      tool = tools[tool_call.name]
      args = tool_call.arguments
      tool.call(args)
    end

    def add_message(message_or_attributes)
      message = message_or_attributes.is_a?(Message) ? message_or_attributes : Message.new(message_or_attributes)
      messages << message
      message
    end

    def add_tool_result(tool_use_id, result)
      add_message(
        role: :tool,
        content: result.is_a?(Hash) && result[:error] ? result[:error] : result.to_s,
        tool_call_id: tool_use_id
      )
    end

    def ensure_valid_tools
      tools.each_key do |name|
        unless name.is_a?(String) && tools[name].is_a?(RubyLLM::Tool)
          raise Error, 'Tools should be of the format {<name>: <RubyLLM::Tool>}'
        end
      end
    end
  end
end
