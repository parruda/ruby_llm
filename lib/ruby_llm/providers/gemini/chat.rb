# frozen_string_literal: true

module RubyLLM
  module Providers
    class Gemini
      # Chat methods for the Gemini API implementation
      module Chat
        module_function

        def completion_url
          "models/#{@model}:generateContent"
        end

        def render_payload(messages, tools:, temperature:, model:, stream: false, schema: nil) # rubocop:disable Metrics/ParameterLists,Lint/UnusedMethodArgument
          @model = model.id
          payload = {
            contents: format_messages(messages),
            generationConfig: {}
          }

          payload[:generationConfig][:temperature] = temperature unless temperature.nil?

          if schema
            payload[:generationConfig][:responseMimeType] = 'application/json'
            payload[:generationConfig][:responseSchema] = convert_schema_to_gemini(schema)
          end

          payload[:tools] = format_tools(tools) if tools.any?
          payload
        end

        private

        def format_messages(messages)
          formatter = MessageFormatter.new(
            messages,
            format_role: method(:format_role),
            format_parts: method(:format_parts),
            format_tool_result: method(:format_tool_result)
          )
          formatter.format
        end

        def format_role(role)
          case role
          when :assistant then 'model'
          when :system then 'user'
          when :tool then 'function'
          else role.to_s
          end
        end

        def format_parts(msg)
          if msg.tool_call?
            format_tool_call(msg)
          elsif msg.tool_result?
            format_tool_result(msg)
          else
            Media.format_content(msg.content)
          end
        end

        def parse_completion_response(response)
          data = response.body
          tool_calls = extract_tool_calls(data)

          Message.new(
            role: :assistant,
            content: parse_content(data),
            tool_calls: tool_calls,
            input_tokens: data.dig('usageMetadata', 'promptTokenCount'),
            output_tokens: calculate_output_tokens(data),
            model_id: data['modelVersion'] || response.env.url.path.split('/')[3].split(':')[0],
            raw: response
          )
        end

        def convert_schema_to_gemini(schema)
          return nil unless schema

          schema = normalize_any_of(schema) if schema[:anyOf]

          build_base_schema(schema).tap do |result|
            result[:description] = schema[:description] if schema[:description]
            apply_type_specific_attributes(result, schema)
          end
        end

        def normalize_any_of(schema)
          any_of_schemas = schema[:anyOf]
          null_schemas = any_of_schemas.select { |s| s[:type] == 'null' }
          non_null_schemas = any_of_schemas.reject { |s| s[:type] == 'null' }

          return non_null_schemas.first.merge(nullable: true) if non_null_schemas.size == 1 && null_schemas.any?

          return non_null_schemas.first if non_null_schemas.any?

          { type: 'string', nullable: true }
        end

        def parse_content(data)
          candidate = data.dig('candidates', 0)
          return '' unless candidate

          return '' if function_call?(candidate)

          parts = candidate.dig('content', 'parts')
          return '' unless parts&.any?

          build_response_content(parts)
        end

        def function_call?(candidate)
          parts = candidate.dig('content', 'parts')
          parts&.any? { |p| p['functionCall'] }
        end

        def calculate_output_tokens(data)
          candidates = data.dig('usageMetadata', 'candidatesTokenCount') || 0
          thoughts = data.dig('usageMetadata', 'thoughtsTokenCount') || 0
          candidates + thoughts
        end

        def build_base_schema(schema)
          case schema[:type]
          when 'object'
            build_object_schema(schema)
          when 'array'
            { type: 'ARRAY', items: schema[:items] ? convert_schema_to_gemini(schema[:items]) : { type: 'STRING' } }
          when 'number'
            { type: 'NUMBER' }
          when 'integer'
            { type: 'INTEGER' }
          when 'boolean'
            { type: 'BOOLEAN' }
          else
            { type: 'STRING' }
          end
        end

        def build_object_schema(schema)
          {
            type: 'OBJECT',
            properties: (schema[:properties] || {}).transform_values { |prop| convert_schema_to_gemini(prop) },
            required: schema[:required] || []
          }.tap do |object|
            object[:propertyOrdering] = schema[:propertyOrdering] if schema[:propertyOrdering]
            object[:nullable] = schema[:nullable] if schema.key?(:nullable)
          end
        end

        def apply_type_specific_attributes(result, schema)
          case schema[:type]
          when 'string'
            copy_attributes(result, schema, :enum, :format, :nullable)
          when 'number', 'integer'
            copy_attributes(result, schema, :format, :minimum, :maximum, :enum, :nullable)
          when 'array'
            copy_attributes(result, schema, :minItems, :maxItems, :nullable)
          when 'boolean'
            copy_attributes(result, schema, :nullable)
          end
        end

        def copy_attributes(target, source, *attributes)
          attributes.each do |attr|
            target[attr] = source[attr] if attr == :nullable ? source.key?(attr) : source[attr]
          end
        end

        class MessageFormatter
          def initialize(messages, format_role:, format_parts:, format_tool_result:)
            @messages = messages
            @index = 0
            @tool_call_names = {}
            @format_role = format_role
            @format_parts = format_parts
            @format_tool_result = format_tool_result
          end

          def format
            formatted = []

            while current_message
              if tool_message?(current_message)
                tool_parts, next_index = collect_tool_parts
                formatted << build_tool_response(tool_parts)
                @index = next_index
              else
                remember_tool_calls if current_message.tool_call?
                formatted << build_standard_message(current_message)
                @index += 1
              end
            end

            formatted
          end

          private

          def current_message
            @messages[@index]
          end

          def tool_message?(message)
            message&.role == :tool
          end

          def collect_tool_parts
            parts = []
            index = @index

            while tool_message?(@messages[index])
              tool_message = @messages[index]
              tool_name = @tool_call_names.delete(tool_message.tool_call_id)
              parts.concat(format_tool_result(tool_message, tool_name))
              index += 1
            end

            [parts, index]
          end

          def build_tool_response(parts)
            { role: 'function', parts: parts }
          end

          def remember_tool_calls
            current_message.tool_calls.each do |tool_call_id, tool_call|
              @tool_call_names[tool_call_id] = tool_call.name
            end
          end

          def build_standard_message(message)
            {
              role: @format_role.call(message.role),
              parts: @format_parts.call(message)
            }
          end

          def format_tool_result(message, tool_name)
            @format_tool_result.call(message, tool_name)
          end
        end
      end
    end
  end
end
