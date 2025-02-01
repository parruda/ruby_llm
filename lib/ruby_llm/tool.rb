# frozen_string_literal: true

module RubyLLM
  class Tool
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

    class Builder
      def initialize(tool)
        @tool = tool
      end

      def description(text)
        @tool.instance_variable_set(:@description, text)
        self
      end

      def param(name, type: 'string', description: nil, required: true)
        @tool.parameters[name] = Parameter.new(name, type: type, description: description, required: required)
        self
      end

      def handler(&block)
        @tool.instance_variable_set(:@handler, block)
        @tool
      end
    end

    attr_reader :name, :description, :parameters, :handler

    def self.define(name, &block)
      tool = new(name)
      builder = Builder.new(tool)
      builder.instance_eval(&block)
      tool
    end

    def initialize(name)
      @name = name
      @parameters = {}
    end

    def call(args)
      raise Error, "No handler defined for tool #{name}" unless @handler

      begin
        args = symbolize_keys(args)
        @handler.call(args)
      rescue StandardError => e
        { error: e.message }
      end
    end

    class << self
      def from_method(method, description: nil)
        define(method.name.to_s) do
          description description if description

          method.parameters.each do |type, name|
            param name, required: (type == :req)
          end

          handler do |args|
            method.owner.new.public_send(method.name, **args)
          end
        end
      end
    end

    private

    def symbolize_keys(hash)
      hash.transform_keys do |key|
        key.to_sym
      rescue StandardError
        key
      end
    end
  end
end
