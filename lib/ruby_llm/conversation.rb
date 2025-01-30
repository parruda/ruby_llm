# frozen_string_literal: true

module RubyLLM
  # Represents a conversation with an LLM
  class Conversation
    attr_reader :id, :messages, :tools

    def initialize(tools: [])
      @id = SecureRandom.uuid
      @messages = []
      @tools = tools
    end

    def add_message(message)
      @messages << message
      message
    end
  end
end
