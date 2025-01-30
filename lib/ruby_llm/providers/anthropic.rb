# frozen_string_literal: true

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

      private

      def tool_to_anthropic(tool)
        {
          name: tool.name,
          description: tool.description,
          input_schema: {
            type: 'object',
            properties: tool.parameters,
            required: tool.parameters.select { |_, v| v[:required] }.keys
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

      def create_chat_completion(payload, tools = nil)
        response = @connection.post('/v1/messages') do |req|
          req.headers['x-api-key'] = RubyLLM.configuration.anthropic_api_key
          req.headers['anthropic-version'] = '2023-06-01'
          req.headers['Content-Type'] = 'application/json'
          req.body = payload
        end

        puts 'Response from Anthropic:' if ENV['RUBY_LLM_DEBUG']
        puts JSON.pretty_generate(response.body) if ENV['RUBY_LLM_DEBUG']

        handle_response(response, tools, payload)
      rescue Faraday::Error => e
        handle_error(e)
      end

      def stream_chat_completion(payload, tools = nil)
        response = @connection.post('/v1/messages') do |req|
          req.headers['x-api-key'] = RubyLLM.configuration.anthropic_api_key
          req.headers['anthropic-version'] = '2023-06-01'
          req.body = payload
        end

        response.body.each_line do |line|
          next if line.strip.empty?
          next if line == 'data: [DONE]'

          begin
            data = JSON.parse(line.sub(/^data: /, ''))

            if data['type'] == 'content_block_delta'
              content = data['delta']['text']
              yield Message.new(role: :assistant, content: content) if content
            elsif data['type'] == 'tool_call'
              handle_tool_calls(data['tool_calls'], tools) do |result|
                yield Message.new(role: :assistant, content: result)
              end
            end
          rescue JSON::ParserError
            next
          end
        end
      rescue Faraday::Error => e
        handle_error(e)
      end

      def handle_response(response, tools, payload)
        data = response.body
        return Message.new(role: :assistant, content: '') if data['type'] == 'error'

        # Extract text content and tool use from response
        content_parts = data['content'] || []
        text_content = content_parts.find { |c| c['type'] == 'text' }&.fetch('text', '')
        tool_use = content_parts.find { |c| c['type'] == 'tool_use' }

        if tool_use && tools
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

          # Create a new message with the tool result
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

          return create_chat_completion(payload.merge(messages: new_messages), tools)
        end

        Message.new(
          role: :assistant,
          content: text_content
        )
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

      def api_base
        'https://api.anthropic.com'
      end
    end
  end
end
