# frozen_string_literal: true

# lib/ruby_llm/tool.rb
module RubyLLM
  class Tool
    class << self
      def description(text = nil)
        return @description unless text

        @description = text
      end

      def param(name, type:, desc: nil, required: true)
        param = Parameter.new(
          name,
          type: type.to_s,
          description: desc,
          required: required
        )
        parameters[name] = param
      end

      def parameters
        @parameters ||= {}
      end

      def name
        super
          .gsub(/([A-Z]+)([A-Z][a-z])/, '\1_\2')
          .gsub(/([a-z\d])([A-Z])/, '\1_\2')
          .downcase
          .delete_suffix('_tool')
      end

      def to_tool
        tool_instance = new

        def tool_instance.name
          self.class.name
        end

        def tool_instance.description
          self.class.description
        end

        def tool_instance.parameters
          self.class.parameters
        end

        tool_instance
      end
    end

    def call(args)
      RubyLLM.logger.debug "Tool #{name} called with: #{args.inspect}"
      result = execute(args.transform_keys(&:to_sym))
      RubyLLM.logger.debug "Tool #{name} returned: #{result.inspect}"
      result
    rescue StandardError => e
      RubyLLM.logger.error "Tool #{name} failed with error: #{e.message}"
      { error: e.message }
    end

    private

    def execute(args)
      raise NotImplementedError, 'Subclasses must implement #execute'
    end
  end

  # Using the existing Parameter class from Tool.rb
  class Parameter
    attr_reader :name, :type, :description, :required

    def initialize(name, type: 'string', description: nil, required: true)
      @name = name
      @type = type
      @description = description
      @required = required
    end

    def to_h
      {
        type: type,
        description: description,
        required: required
      }.compact
    end
  end
end
