# frozen_string_literal: true

module RubyLLM
  module Providers
    # OpenAI Responses API provider.
    # Uses v1/responses endpoint instead of v1/chat/completions.
    # Inherits from OpenAI and overrides only what differs.
    class OpenAIResponses < OpenAI
      attr_reader :responses_session, :responses_config

      def initialize(config, responses_session = nil, responses_config = {})
        @responses_session = responses_session || ResponsesSession.new
        @responses_config = {
          stateful: false,
          store: true,
          truncation: :disabled,
          include: []
        }.merge(responses_config)

        super(config)
      end

      # Override endpoint URL - no conditionals needed
      def completion_url
        'responses'
      end

      # Override complete to handle response ID failures
      def complete(messages, tools:, temperature:, model:, params: {}, headers: {}, schema: nil, &block) # rubocop:disable Metrics/ParameterLists
        super
      rescue BadRequestError => e
        raise unless response_id_not_found_error?(e)

        handle_response_id_failure
        retry
      end

      # Override render_payload for Responses API format
      def render_payload(messages, tools:, temperature:, model:, stream: false, schema: nil) # rubocop:disable Metrics/ParameterLists
        system_msgs, other_msgs = partition_messages(messages)

        payload = build_base_payload(model, stream)
        add_instructions(payload, system_msgs)
        add_input(payload, other_msgs)
        add_temperature(payload, temperature)
        add_tools(payload, tools)
        add_schema(payload, schema)
        add_optional_parameters(payload)
        add_stream_options(payload, stream)

        payload
      end

      # Override parse_completion_response for Responses API format
      def parse_completion_response(response)
        data = response.body
        return if data.nil? || !data.is_a?(Hash) || data.empty?

        # Check status first to handle failed responses appropriately
        case data['status']
        when 'completed'
          parse_completed_response(data, response)
        when 'failed'
          raise ResponseFailedError.new(response, data.dig('error', 'message') || 'Response failed')
        when 'in_progress', 'queued'
          raise ResponseInProgressError.new(response, "Response still processing: #{data['id']}")
        when 'cancelled'
          raise ResponseCancelledError.new(response, "Response was cancelled: #{data['id']}")
        when 'incomplete'
          parse_incomplete_response(data, response)
        else
          # For responses without status, check for error
          raise Error.new(response, data.dig('error', 'message')) if data.dig('error', 'message')

          parse_completed_response(data, response)
        end
      end

      # Override tool_for for flat format (not nested under 'function')
      def tool_for(tool)
        parameters_schema = parameters_schema_for(tool)

        definition = {
          type: 'function',
          name: tool.name,
          description: tool.description,
          parameters: parameters_schema
        }

        return definition if tool.provider_params.empty?

        RubyLLM::Utils.deep_merge(definition, tool.provider_params)
      end

      # Override build_chunk for Responses API streaming events
      def build_chunk(data)
        if responses_api_event?(data)
          build_responses_chunk(data)
        else
          super
        end
      end

      private

      def stateful_mode?
        @responses_config[:stateful] == true
      end

      def partition_messages(messages)
        system_msgs = messages.select { |m| m.role == :system }
        other_msgs = messages.reject { |m| m.role == :system }
        [system_msgs, other_msgs]
      end

      def build_base_payload(model, stream)
        {
          model: model.id,
          stream: stream,
          store: @responses_config[:store]
        }
      end

      def add_instructions(payload, system_msgs)
        payload[:instructions] = format_instructions(system_msgs) if system_msgs.any?
      end

      def add_input(payload, other_msgs)
        if stateful_mode? && @responses_session.valid?
          payload[:previous_response_id] = @responses_session.response_id
          payload[:input] = format_new_input_only(other_msgs)
        else
          payload[:input] = format_responses_input(other_msgs)
        end
      end

      def add_temperature(payload, temperature)
        payload[:temperature] = temperature unless temperature.nil?
      end

      def add_tools(payload, tools)
        payload[:tools] = tools.map { |_, tool| tool_for(tool) } if tools.any?
      end

      def add_schema(payload, schema)
        return unless schema

        payload[:text] = {
          format: {
            type: 'json_schema',
            name: 'response',
            schema: schema,
            strict: schema[:strict] != false
          }
        }
      end

      def add_stream_options(payload, stream)
        payload[:stream_options] = { include_usage: true } if stream
      end

      def response_id_not_found_error?(error)
        return false unless @responses_session.response_id

        error.message.include?('not found')
      end

      def handle_response_id_failure
        @responses_session.record_failure!

        if @responses_session.disabled?
          RubyLLM.logger.warn('Responses API: Disabling stateful mode after repeated failures')
        else
          RubyLLM.logger.debug('Responses API: Response ID not found, retrying fresh')
        end
      end

      def format_instructions(system_messages)
        system_messages.map { |m| m.content.to_s }.join("\n\n")
      end

      def format_responses_input(messages)
        messages.filter_map do |msg|
          case msg.role
          when :user
            {
              type: 'message',
              role: 'user',
              content: format_input_content(msg.content)
            }
          when :assistant
            next if msg.content.nil? || msg.content.to_s.strip.empty?

            {
              type: 'message',
              role: 'assistant',
              content: format_output_content(msg.content)
            }
          when :tool
            {
              type: 'function_call_output',
              call_id: msg.tool_call_id,
              output: msg.content.to_s
            }
          end
        end
      end

      def format_new_input_only(messages)
        formatted = []
        last_assistant_idx = messages.rindex { |msg| msg.role == :assistant }

        if last_assistant_idx
          new_messages = messages[(last_assistant_idx + 1)..]
          new_messages.each do |msg|
            case msg.role
            when :tool
              formatted << {
                type: 'function_call_output',
                call_id: msg.tool_call_id,
                output: msg.content.to_s
              }
            when :user
              formatted << {
                type: 'message',
                role: 'user',
                content: format_input_content(msg.content)
              }
            end
          end
        else
          messages.each do |msg|
            next unless msg.role == :user

            formatted << {
              type: 'message',
              role: 'user',
              content: format_input_content(msg.content)
            }
          end
        end

        formatted
      end

      def format_input_content(content)
        case content
        when String
          [{ type: 'input_text', text: content }]
        when Content
          parts = []
          parts << { type: 'input_text', text: content.text } if content.text && !content.text.empty?
          content.attachments.each do |attachment|
            parts << format_input_attachment(attachment)
          end
          parts
        when Content::Raw
          content.value
        else
          [{ type: 'input_text', text: content.to_s }]
        end
      end

      def format_output_content(content)
        if content.is_a?(String)
          [{ type: 'output_text', text: content }]
        elsif content.is_a?(Content)
          [{ type: 'output_text', text: content.text || '' }]
        else
          [{ type: 'output_text', text: content.to_s }]
        end
      end

      def format_input_attachment(attachment)
        case attachment.type
        when :image
          if attachment.url?
            { type: 'input_image', image_url: attachment.source.to_s }
          else
            { type: 'input_image', image_url: attachment.for_llm }
          end
        when :file, :pdf
          { type: 'input_file', file_data: attachment.encoded, filename: attachment.filename }
        else
          { type: 'input_text', text: "[Unsupported attachment: #{attachment.type}]" }
        end
      end

      def add_optional_parameters(payload)
        if @responses_config[:truncation] && @responses_config[:truncation] != :disabled
          payload[:truncation] = @responses_config[:truncation].to_s
        end

        if @responses_config[:include] && !@responses_config[:include].empty?
          payload[:include] = @responses_config[:include].map { |i| i.to_s.tr('_', '.') }
        end

        payload[:service_tier] = @responses_config[:service_tier].to_s if @responses_config[:service_tier]
        payload[:max_tool_calls] = @responses_config[:max_tool_calls] if @responses_config[:max_tool_calls]
      end

      def parse_completed_response(data, response)
        output = data['output'] || []
        content_parts = []
        tool_calls = {}

        output.each do |item|
          case item['type']
          when 'message'
            content_parts << extract_message_content(item)
          when 'function_call'
            tool_calls[item['call_id']] = ToolCall.new(
              id: item['call_id'],
              name: item['name'],
              arguments: parse_tool_arguments(item['arguments'])
            )
          end
        end

        usage = data['usage'] || {}

        Message.new(
          role: :assistant,
          content: content_parts.join("\n"),
          tool_calls: tool_calls.empty? ? nil : tool_calls,
          response_id: data['id'],
          reasoning_summary: data.dig('reasoning', 'summary'),
          reasoning_tokens: usage.dig('output_tokens_details', 'reasoning_tokens'),
          input_tokens: usage['input_tokens'] || 0,
          output_tokens: usage['output_tokens'] || 0,
          cached_tokens: usage.dig('prompt_tokens_details', 'cached_tokens'),
          cache_creation_tokens: 0,
          model_id: data['model'],
          raw: response
        )
      end

      def parse_tool_arguments(arguments)
        if arguments.nil? || arguments.empty?
          {}
        elsif arguments.is_a?(String)
          JSON.parse(arguments)
        else
          arguments
        end
      rescue JSON::ParserError
        {}
      end

      def parse_incomplete_response(data, response)
        message = parse_completed_response(data, response)
        RubyLLM.logger.warn("Responses API: Incomplete response: #{data['incomplete_details']}")
        message
      end

      def extract_message_content(item)
        return '' unless item['content'].is_a?(Array)

        item['content'].filter_map do |content_item|
          content_item['text'] if content_item['type'] == 'output_text'
        end.join
      end

      def responses_api_event?(data)
        data.is_a?(Hash) && data['type']&.start_with?('response.')
      end

      def build_responses_chunk(data)
        case data['type']
        when 'response.content_part.delta'
          Chunk.new(
            role: :assistant,
            content: data.dig('delta', 'text') || '',
            model_id: nil,
            input_tokens: nil,
            output_tokens: nil
          )
        when 'response.completed'
          usage = data.dig('response', 'usage') || {}
          Chunk.new(
            role: :assistant,
            content: nil,
            model_id: data.dig('response', 'model'),
            input_tokens: usage['input_tokens'],
            output_tokens: usage['output_tokens'],
            cached_tokens: usage.dig('prompt_tokens_details', 'cached_tokens'),
            cache_creation_tokens: 0
          )
        else
          Chunk.new(role: :assistant, content: nil, model_id: nil, input_tokens: nil, output_tokens: nil)
        end
      end
    end
  end
end
