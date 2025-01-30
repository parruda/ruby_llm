# frozen_string_literal: true

module RubyLLM
  # Represents a message in an LLM conversation
  class Message
    VALID_ROLES = %i[system user assistant tool].freeze

    attr_reader :role, :content, :tool_calls, :tool_results

    def initialize(role:, content: nil, tool_calls: nil, tool_results: nil)
      @role = role.to_sym
      @content = content
      @tool_calls = tool_calls
      @tool_results = tool_results
      validate!
    end

    def to_h
      {
        role: role,
        content: content,
        tool_calls: tool_calls,
        tool_results: tool_results
      }.compact
    end

    private

    def validate!
      return if VALID_ROLES.include?(role)

      raise ArgumentError, "Invalid role: #{role}. Must be one of: #{VALID_ROLES.join(', ')}"
    end
  end
end
