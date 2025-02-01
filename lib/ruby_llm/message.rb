# frozen_string_literal: true

module RubyLLM
  class Message
    ROLES = %i[system user assistant tool].freeze

    attr_reader :role, :content, :tool_calls, :tool_results, :input_tokens, :output_tokens, :model_id

    def initialize(options = {})
      @role = options[:role].to_sym
      @content = options[:content]
      @tool_calls = options[:tool_calls]
      @tool_results = options[:tool_results]
      @input_tokens = options[:input_tokens]
      @output_tokens = options[:output_tokens]
      @model_id = options[:model_id]

      ensure_valid_role
    end

    def tool_call?
      !tool_calls.nil? && !tool_calls.empty?
    end

    def tool_result?
      !tool_results.nil? && !tool_results.empty?
    end

    def to_h
      {
        role: role,
        content: content,
        tool_calls: tool_calls,
        tool_results: tool_results,
        input_tokens: input_tokens,
        output_tokens: output_tokens,
        model_id: model_id
      }.compact
    end

    private

    def ensure_valid_role
      raise Error, "Expected role to be one of: #{ROLES.join(', ')}" unless ROLES.include?(role)
    end
  end
end
