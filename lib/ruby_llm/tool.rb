# frozen_string_literal: true

module RubyLLM
  class Parameter
    attr_reader :name, :type, :description, :required

    def initialize(name, type: 'string', desc: nil, required: true)
      @name = name
      @type = type
      @description = desc
      @required = required
    end
  end

  class Tool
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
      self.class.name
          .gsub(/([A-Z]+)([A-Z][a-z])/, '\1_\2')
          .gsub(/([a-z\d])([A-Z])/, '\1_\2')
          .downcase
          .delete_suffix('_tool')
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
    rescue StandardError => e
      RubyLLM.logger.error "Tool #{name} failed with error: #{e.message}"
      { error: e.message }
    end

    def execute(...)
      raise NotImplementedError, 'Subclasses must implement #execute'
    end
  end
end
