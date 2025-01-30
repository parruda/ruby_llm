# frozen_string_literal: true

require 'time'

module RubyLLM
  module Providers
    class Anthropic < Base
      def chat(messages, model: nil, temperature: 0.7, stream: false, tools: nil, &block)
        payload = {
          model: model || 'claude-3-5-sonnet-20241022',
          messages: format_messages(messages),
          temperature: temperature,
          stream: stream,
          max_tokens: 4096
        }

        payload[:tools] = tools.map { |tool| tool_to_anthropic(tool) } if tools&.any?

        puts 'Sending payload to Anthropic:' if ENV['RUBY_LLM_DEBUG']
        puts JSON.pretty_generate(payload) if ENV['RUBY_LLM_DEBUG']

        if stream && block_given?
          stream_chat_completion(payload, tools, &block)
        else
          create_chat_completion(payload, tools)
        end
      end

      def list_models
        response = @connection.get('/v1/models') do |req|
          req.headers['x-api-key'] = RubyLLM.configuration.anthropic_api_key
          req.headers['anthropic-version'] = '2023-06-01'
        end

        raise RubyLLM::Error, "API error: #{parse_error_message(response)}" if response.status >= 400

        capabilities = RubyLLM::ModelCapabilities::Anthropic.new
        models_data = response.body['data'] || []

        models_data.map do |model|
          ModelInfo.new(
            id: model['id'],
            created_at: Time.parse(model['created_at']),
            display_name: model['display_name'],
            provider: 'anthropic',
            metadata: {
              type: model['type']
            },
            context_window: capabilities.determine_context_window(model['id']),
            max_tokens: capabilities.determine_max_tokens(model['id']),
            supports_vision: capabilities.supports_vision?(model['id']),
            supports_functions: capabilities.supports_functions?(model['id']),
            supports_json_mode: capabilities.supports_json_mode?(model['id']),
            input_price_per_million: capabilities.get_input_price(model['id']),
            output_price_per_million: capabilities.get_output_price(model['id'])
          )
        end
      rescue Faraday::Error => e
        handle_error(e)
      end

      private

      def tool_to_anthropic(tool)
        # Get required fields and clean properties
        required_fields = []
        cleaned_properties = {}

        tool.parameters.each do |name, props|
          required_fields << name.to_s if props[:required]
          cleaned_props = props.dup
          cleaned_props.delete(:required)
          cleaned_properties[name] = cleaned_props
        end

        {
          name: tool.name,
          description: tool.description,
          input_schema: {
            type: 'object',
            properties: cleaned_properties,
            required: required_fields
          }
        }
      end

      def format_messages(messages)
        messages.map do |msg|
          message = { role: msg.role == :user ? 'user' : 'assistant' }

          message[:content] = if msg.tool_results
                                [
                                  {
                                    type: 'tool_result',
                                    tool_use_id: msg.tool_results[:tool_use_id],
                                    content: msg.tool_results[:content],
                                    is_error: msg.tool_results[:is_error]
                                  }.compact
                                ]
                              else
                                msg.content
                              end

          message
        end
      end

      def create_chat_completion(payload, tools = nil, &block)
        response = @connection.post('/v1/messages') do |req|
          req.headers['x-api-key'] = RubyLLM.configuration.anthropic_api_key
          req.headers['anthropic-version'] = '2023-06-01'
          req.headers['Content-Type'] = 'application/json'
          req.body = payload
        end

        puts 'Response from Anthropic:' if ENV['RUBY_LLM_DEBUG']
        puts JSON.pretty_generate(response.body) if ENV['RUBY_LLM_DEBUG']

        # Check for API errors first
        check_for_api_error(response)

        handle_response(response, tools, payload, &block)
      rescue Faraday::Error => e
        handle_error(e)
      end

      def stream_chat_completion(payload, tools = nil)
        response = @connection.post('/v1/messages') do |req|
          req.headers['x-api-key'] = RubyLLM.configuration.anthropic_api_key
          req.headers['anthropic-version'] = '2023-06-01'
          req.body = payload
        end

        messages = []
        response.body.each_line do |line|
          next if line.strip.empty?
          next if line == 'data: [DONE]'

          begin
            data = JSON.parse(line.sub(/^data: /, ''))

            message = case data['type']
                      when 'content_block_delta'
                        Message.new(role: :assistant, content: data['delta']['text']) if data['delta']['text']
                      when 'tool_call'
                        handle_tool_calls(data['tool_calls'], tools) do |result|
                          Message.new(role: :assistant, content: result)
                        end
                      end

            if message
              messages << message
              yield message if block_given?
            end
          rescue JSON::ParserError
            next
          end
        end

        messages
      rescue Faraday::Error => e
        handle_error(e)
      end

      def handle_response(response, tools, payload, &block)
        data = response.body

        content_parts = data['content'] || []
        text_content = content_parts.find { |c| c['type'] == 'text' }&.fetch('text', '')
        tool_use = content_parts.find { |c| c['type'] == 'tool_use' }

        if tool_use && tools
          # Tool call handling code...
          tool_message = Message.new(
            role: :assistant,
            content: text_content,
            tool_calls: [{
              name: tool_use['name'],
              arguments: JSON.generate(tool_use['input'] || {})
            }]
          )
          yield tool_message if block_given?

          tool = tools.find { |t| t.name == tool_use['name'] }
          result = if tool
                     begin
                       tool_result = tool.call(tool_use['input'] || {})
                       {
                         tool_use_id: tool_use['id'],
                         content: tool_result.to_s
                       }
                     rescue StandardError => e
                       {
                         tool_use_id: tool_use['id'],
                         content: "Error executing tool #{tool.name}: #{e.message}",
                         is_error: true
                       }
                     end
                   end

          result_message = Message.new(
            role: :tool,
            content: result[:content],
            tool_results: result
          )
          yield result_message if block_given?

          new_messages = payload[:messages] + [
            { role: 'assistant', content: data['content'] },
            {
              role: 'user',
              content: [
                {
                  type: 'tool_result',
                  tool_use_id: result[:tool_use_id],
                  content: result[:content],
                  is_error: result[:is_error]
                }.compact
              ]
            }
          ]

          final_response = create_chat_completion(
            payload.merge(messages: new_messages),
            tools,
            &block
          )

          [tool_message, result_message] + final_response
        else
          token_usage = if data['usage']
                          {
                            input_tokens: data['usage']['input_tokens'],
                            output_tokens: data['usage']['output_tokens'],
                            total_tokens: data['usage']['input_tokens'] + data['usage']['output_tokens']
                          }
                        end

          [Message.new(
            role: :assistant,
            content: text_content,
            token_usage: token_usage,
            model_id: data['model']
          )]
        end
      end

      def handle_tool_calls(tool_calls, tools)
        return [] unless tool_calls && tools

        tool_calls.map do |tool_call|
          tool = tools.find { |t| t.name == tool_call['name'] }
          next unless tool

          begin
            args = JSON.parse(tool_call['arguments'])
            result = tool.call(args)
            puts "Tool result: #{result}" if ENV['RUBY_LLM_DEBUG']
            {
              tool_use_id: tool_call['id'],
              content: result.to_s
            }
          rescue JSON::ParserError, ArgumentError => e
            puts "Error executing tool: #{e.message}" if ENV['RUBY_LLM_DEBUG']
            {
              tool_use_id: tool_call['id'],
              content: "Error executing tool #{tool.name}: #{e.message}",
              is_error: true
            }
          end
        end.compact
      end

      def handle_api_error(error)
        response_body = error.response[:body]
        if response_body.is_a?(String)
          begin
            error_data = JSON.parse(response_body)
            message = error_data.dig('error', 'message')
            raise RubyLLM::Error, "API error: #{message}" if message
          rescue JSON::ParserError
            raise RubyLLM::Error, "API error: #{error.response[:status]}"
          end
        elsif response_body['error']
          raise RubyLLM::Error, "API error: #{response_body['error']['message']}"
        else
          raise RubyLLM::Error, "API error: #{error.response[:status]}"
        end
      end

      def handle_error(error)
        case error
        when Faraday::TimeoutError
          raise RubyLLM::Error, 'Request timed out'
        when Faraday::ConnectionFailed
          raise RubyLLM::Error, 'Connection failed'
        when Faraday::ClientError
          handle_api_error(error)
        else
          raise error
        end
      end

      def api_base
        'https://api.anthropic.com'
      end
    end
  end
end
