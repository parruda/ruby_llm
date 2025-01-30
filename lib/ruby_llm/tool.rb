# frozen_string_literal: true

module RubyLLM
  # Represents a tool/function that can be called by an LLM
  class Tool
    attr_reader :name, :description, :parameters, :handler

    def self.from_method(method_object, description: nil, parameter_descriptions: {})
      method_params = {}
      method_object.parameters.each do |param_type, param_name|
        next unless %i[req opt key keyreq].include?(param_type)

        method_params[param_name] = {
          type: 'string',
          description: parameter_descriptions[param_name] || param_name.to_s.tr('_', ' '),
          required: %i[req keyreq].include?(param_type)
        }
      end

      new(
        name: method_object.name.to_s,
        description: description || "Executes the #{method_object.name} operation",
        parameters: method_params
      ) do |args|
        # Create an instance if it's an instance method
        instance = if method_object.owner.instance_methods.include?(method_object.name)
                     method_object.owner.new
                   else
                     method_object.owner
                   end

        # Call the method with the arguments
        if args.is_a?(Hash)
          instance.method(method_object.name).call(**args)
        else
          instance.method(method_object.name).call(args)
        end
      end
    end

    def initialize(name:, description:, parameters: {}, &block)
      @name = name
      @description = description
      @parameters = parameters
      @handler = block

      validate!
    end

    def call(args)
      validated_args = validate_args!(args)
      handler.call(validated_args)
    end

    private

    def validate!
      raise ArgumentError, 'Name must be a string' unless name.is_a?(String)
      raise ArgumentError, 'Description must be a string' unless description.is_a?(String)
      raise ArgumentError, 'Parameters must be a hash' unless parameters.is_a?(Hash)
      raise ArgumentError, 'Block must be provided' unless handler.respond_to?(:call)
    end

    def validate_args!(args)
      args = args.transform_keys(&:to_sym)
      required_params = parameters.select { |_, v| v[:required] }.keys

      required_params.each do |param|
        raise ArgumentError, "Missing required parameter: #{param}" unless args.key?(param.to_sym)
      end

      args
    end
  end
end
