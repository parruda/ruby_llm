# frozen_string_literal: true

module RubyLLM
  # Parameter definition for Tool methods.
  class Parameter
    attr_reader :name, :type, :description, :required

    def initialize(name, type: 'string', desc: nil, required: true)
      @name = name
      @type = type
      @description = desc
      @required = required
    end
  end

  # Base class for creating tools that AI models can use
  class Tool
    # Stops conversation continuation after tool execution
    class Halt
      attr_reader :content

      def initialize(content)
        @content = content
      end

      def to_s
        @content.to_s
      end
    end

    class << self
      def description(text = nil)
        return @description unless text

        @description = text
      end

      def param(name, **options)
        parameters[name] = Parameter.new(name, **options)
      end

      def parameters
        @parameters ||= {}
      end
    end

    def name
      Utils.parameterize(self.class.name, separator: '-').delete_suffix('_tool')
    end

    def description
      self.class.description
    end

    def parameters
      self.class.parameters
    end

    def call(args)
      RubyLLM.logger.debug "Tool #{name} called with: #{args.inspect}"
      result = execute(**args.transform_keys(&:to_sym))
      RubyLLM.logger.debug "Tool #{name} returned: #{result.inspect}"
      result
    end

    def execute(...)
      raise NotImplementedError, 'Subclasses must implement #execute'
    end

    protected

    def halt(message)
      Halt.new(message)
    end
  end
end
