# frozen_string_literal: true

module RubyLLM
  class ToolCall
    attr_reader :id, :name, :arguments

    def initialize(id:, name:, arguments: {})
      @id = id
      @name = name
      @arguments = arguments
    end
  end
end
