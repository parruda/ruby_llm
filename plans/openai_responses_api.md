# OpenAI Responses API Support for RubyLLM

## Motivation

### Why Add Responses API Support?

OpenAI's Responses API (`v1/responses`) represents the future of their API surface. This new endpoint:

1. **Enables New Model Capabilities**: Models like `gpt-5-pro`, `o1`, `o3`, and future reasoning models are designed to work with the Responses API. Some models may ONLY be available through this endpoint.

2. **Provides Reasoning Insights**: The API exposes reasoning token usage and optional summaries, allowing developers to understand model behavior and optimize costs for reasoning-intensive tasks.

3. **Supports Stateful Conversations**: The API offers `previous_response_id` with `store: true`, allowing the server to maintain conversation context. This dramatically reduces payload sizes for multi-turn conversations.

4. **Improves Token Efficiency**: With stateful mode, developers save significant tokens and costs by only sending new input (tool results, user messages) rather than the full conversation history.

5. **Advanced Features**: Built-in tools (web search, file search, code interpreter), background processing, conversation objects, and token counting endpoints.

6. **Future-Proofs RubyLLM**: As OpenAI transitions more capabilities to the Responses API, RubyLLM needs native support to remain relevant for the Ruby AI community.

### Target Users

- **AI Application Developers**: Building conversational agents, assistants, and multi-turn applications
- **Cost-Conscious Teams**: Wanting efficient token usage through stateful conversations
- **Early Adopters**: Testing new OpenAI models (o-series, GPT-5) that require this endpoint
- **Researchers**: Analyzing reasoning token usage for model behavior studies

### Value Proposition

By adding native Responses API support, RubyLLM will:
- Be among the first Ruby gems to support OpenAI's next-generation API
- Enable Ruby developers to access the latest AI models
- Offer significant cost savings through stateful conversation management
- Provide clean, idiomatic Ruby API that matches RubyLLM's patterns
- Maintain backward compatibility with existing code

---

## Executive Summary

This plan outlines how to add OpenAI Responses API support to RubyLLM in an idiomatic way that:

1. **Separate provider class** - `OpenAIResponses` inherits from `OpenAI` for clean separation
2. **No conditional logic** - Each provider method is pure and focused
3. **Explicit opt-in** - User calls `with_responses_api` to switch providers
4. **Default to chat/completions** - Standard OpenAI endpoint remains the default
5. **Backward compatible** - No breaking changes to existing APIs
6. **Follows RubyLLM idioms** - Fluent API, inheritance, no reflection methods

---

## Key API Corrections

Based on analysis of the actual OpenAI Responses API documentation:

### 1. Instructions are SEPARATE from Input

**WRONG:**
```ruby
input: [
  { role: "developer", content: "System prompt" },  # WRONG
  { role: "user", content: "User message" }
]
```

**CORRECT:**
```ruby
{
  instructions: "System prompt",  # Separate parameter
  input: [
    { role: "user", content: [...] }  # Only user/assistant messages
  ]
}
```

### 2. Content Uses Typed Items

**WRONG:**
```ruby
{ role: "user", content: "Hello" }  # Plain string
```

**CORRECT:**
```ruby
{
  role: "user",
  content: [
    { type: "input_text", text: "Hello" }  # Typed item
  ]
}
```

### 3. Reasoning is Response Metadata (Not Output Array)

**CORRECT:**
```ruby
{
  reasoning: {
    effort: "medium",
    summary: "The model considered..."  # Separate object
  },
  output: [
    { type: "message", content: [...] }
  ],
  usage: {
    output_tokens_details: {
      reasoning_tokens: 1542  # Token count here
    }
  }
}
```

---

## Architecture Overview

### Separate Provider Class Pattern (Clean Approach)

```
lib/ruby_llm/providers/
├── openai.rb                    # Existing - chat/completions
└── openai_responses.rb          # NEW - v1/responses (inherits from OpenAI)
```

The `OpenAIResponses` class **inherits from `OpenAI`** and overrides only the methods that differ. No conditional logic needed.

### Key Design Decisions

1. **Inheritance over composition**: `OpenAIResponses < OpenAI` provides clean separation
2. **No conditionals**: Each method does one thing, no `if using_responses_api?` checks
3. **Provider-level config**: Responses configuration stored in provider instance
4. **Chat switches providers**: `with_responses_api` creates new provider instance
5. **Session in Chat**: Per-conversation state stays in Chat class
6. **No reflection methods**: Proper keyword argument initialization
7. **No provider registration**: OpenAIResponses is NOT registered in `Provider.providers`, it's an upgrade of OpenAI for the same models

### Model Resolution (Unchanged)

Model resolution is completely unaffected because:

1. **Same models**: OpenAI models (gpt-4o, o3, etc.) are used with both endpoints
2. **No registration**: OpenAIResponses is not a registered provider - it's not discoverable via model lookup
3. **Upgrade path**: Chat uses normal OpenAI provider, then upgrades to OpenAIResponses when user opts in
4. **Inheritance**: OpenAIResponses inherits all OpenAI configuration (API keys, headers, etc.)

```ruby
# Normal resolution returns OpenAI provider
chat = RubyLLM.chat(model: 'gpt-4o')
# → Models.resolve('gpt-4o') → [model_info, OpenAI.new(config)]

# with_responses_api upgrades to OpenAIResponses (same model)
chat.with_responses_api(stateful: true)
# → @provider = OpenAIResponses.new(config, session, config)
# → @model unchanged, same gpt-4o
```

This keeps model resolution simple and avoids duplication.

---

## Detailed Implementation Plan

### Phase 1: Core Infrastructure

#### 1.1 Add ResponsesSession State Manager

**File**: `lib/ruby_llm/responses_session.rb`

```ruby
# frozen_string_literal: true

module RubyLLM
  # Manages state for OpenAI Responses API stateful conversations.
  class ResponsesSession
    RESPONSE_ID_TTL = 300  # 5 minutes
    MAX_FAILURES = 2

    attr_reader :response_id, :last_activity, :failure_count

    def initialize(response_id: nil, last_activity: nil, failure_count: 0, disabled: false)
      @response_id = response_id
      @last_activity = last_activity
      @failure_count = failure_count
      @disabled = disabled
    end

    def reset!
      @response_id = nil
      @last_activity = nil
      @failure_count = 0
      @disabled = false
    end

    def update(new_response_id)
      @response_id = new_response_id
      @last_activity = Time.now
      @failure_count = 0
    end

    def valid?
      !@disabled &&
        @response_id &&
        @last_activity &&
        (Time.now - @last_activity) < RESPONSE_ID_TTL
    end

    def record_failure!
      @failure_count += 1
      @disabled = true if @failure_count >= MAX_FAILURES
      reset! unless @disabled
    end

    def disabled?
      @disabled
    end

    def to_h
      {
        response_id: @response_id,
        last_activity: @last_activity&.iso8601,
        failure_count: @failure_count,
        disabled: @disabled
      }
    end

    def self.from_h(hash)
      hash = hash.transform_keys(&:to_sym)
      last_activity = hash[:last_activity] ? Time.parse(hash[:last_activity]) : nil

      new(
        response_id: hash[:response_id],
        last_activity: last_activity,
        failure_count: hash[:failure_count] || 0,
        disabled: hash[:disabled] || false
      )
    end
  end
end
```

#### 1.2 Extend Message Class

**File**: `lib/ruby_llm/message.rb`

Add three new attributes:

```ruby
attr_reader :role, :model_id, :tool_calls, :tool_call_id, :input_tokens, :output_tokens,
            :cached_tokens, :cache_creation_tokens, :raw,
            :response_id,           # NEW
            :reasoning_summary,     # NEW
            :reasoning_tokens       # NEW

def initialize(options = {})
  # ... existing ...
  @response_id = options[:response_id]
  @reasoning_summary = options[:reasoning_summary]
  @reasoning_tokens = options[:reasoning_tokens]
  # ...
end

def to_h
  {
    # ... existing fields ...
    response_id: response_id,
    reasoning_summary: reasoning_summary,
    reasoning_tokens: reasoning_tokens
  }.compact
end
```

#### 1.3 Add Responses API Error Types

**File**: `lib/ruby_llm/error.rb`

```ruby
# Responses API specific errors
class ResponsesApiError < Error; end
class ResponseIdNotFoundError < ResponsesApiError; end
class ResponseFailedError < ResponsesApiError; end
class ResponseInProgressError < ResponsesApiError; end
class ResponseCancelledError < ResponsesApiError; end
class ResponseIncompleteError < ResponsesApiError; end
```

#### 1.4 Extend Chat Class with Fluent API

**File**: `lib/ruby_llm/chat.rb`

```ruby
class Chat
  def initialize(model: nil, provider: nil, assume_model_exists: false, context: nil,
                 tool_concurrency: nil, max_concurrency: nil)
    # ... existing initialization ...

    # NEW: Responses API state
    @responses_api_config = nil
    @responses_session = nil
  end

  # Enable Responses API for this chat
  #
  # @param stateful [Boolean] Use previous_response_id (default: false)
  # @param store [Boolean] Store responses on server (default: true)
  # @param truncation [Symbol] Truncation strategy (default: :disabled)
  # @param include [Array<Symbol>] Additional data to include
  # @return [self] For method chaining
  def with_responses_api(stateful: false, store: true, truncation: :disabled, include: [], **options)
    @responses_api_config = {
      stateful: stateful,
      store: store,
      truncation: truncation,
      include: include,
      service_tier: options[:service_tier],
      max_tool_calls: options[:max_tool_calls]
    }

    # Switch to OpenAIResponses provider if currently using OpenAI
    if @provider.is_a?(Providers::OpenAI) && !@provider.is_a?(Providers::OpenAIResponses)
      @provider = Providers::OpenAIResponses.new(@config, responses_session, @responses_api_config)
      @connection = @provider.connection
    end

    self
  end

  def responses_session
    @responses_session ||= ResponsesSession.new
  end

  def restore_responses_session(session_data)
    @responses_session = ResponsesSession.from_h(session_data)
    self
  end

  def responses_api_enabled?
    @provider.is_a?(Providers::OpenAIResponses)
  end

  def complete(&)
    response = @provider.complete(
      messages,
      tools: @tools,
      temperature: @temperature,
      model: @model,
      params: @params,
      headers: @headers,
      schema: @schema,
      &wrap_streaming_block(&)
    )

    emit(:new_message) unless block_given?

    # Update session if response has response_id
    if response.respond_to?(:response_id) && response.response_id && responses_api_enabled?
      responses_session.update(response.response_id)
    end

    # ... rest of existing complete logic ...
  end
end
```

---

### Phase 2: OpenAIResponses Provider Class

#### 2.1 Create Separate Provider Class

**File**: `lib/ruby_llm/providers/openai_responses.rb`

```ruby
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
      def complete(messages, tools:, temperature:, model:, params: {}, headers: {}, schema: nil, &block)
        super
      rescue BadRequestError => e
        if response_id_not_found_error?(e)
          handle_response_id_failure
          retry
        else
          raise
        end
      end

      # Override render_payload for Responses API format
      def render_payload(messages, tools:, temperature:, model:, stream: false, schema: nil)
        system_msgs = messages.select { |m| m.role == :system }
        other_msgs = messages.reject { |m| m.role == :system }

        payload = {
          model: model.id,
          stream: stream,
          store: @responses_config[:store]
        }

        # Instructions are separate from input
        if system_msgs.any?
          payload[:instructions] = format_instructions(system_msgs)
        end

        # Stateful vs stateless input
        if stateful_mode? && @responses_session.valid?
          payload[:previous_response_id] = @responses_session.response_id
          payload[:input] = format_new_input_only(other_msgs)
        else
          payload[:input] = format_responses_input(other_msgs)
        end

        payload[:temperature] = temperature unless temperature.nil?

        if tools.any?
          payload[:tools] = tools.map { |_, tool| tool_for(tool) }
        end

        if schema
          payload[:text] = {
            format: {
              type: 'json_schema',
              name: 'response',
              schema: schema,
              strict: schema[:strict] != false
            }
          }
        end

        add_optional_parameters(payload)
        payload[:stream_options] = { include_usage: true } if stream
        payload
      end

      # Override parse_completion_response for Responses API format
      def parse_completion_response(response)
        data = response.body
        return if data.nil? || !data.is_a?(Hash) || data.empty?

        if data.dig('error', 'message')
          raise Error.new(response, data.dig('error', 'message'))
        end

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
          parse_completed_response(data, response)
        end
      end

      # Override tool_for for flat format (not nested under 'function')
      def tool_for(tool)
        {
          type: 'function',
          name: tool.name,
          description: tool.description,
          parameters: parameters_schema_for(tool)
        }
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

      def response_id_not_found_error?(error)
        error.message.include?('not found') && @responses_session.response_id
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
        if content.is_a?(String)
          [{ type: 'input_text', text: content }]
        elsif content.is_a?(Content)
          parts = []
          parts << { type: 'input_text', text: content.text } if content.text && !content.text.empty?
          content.attachments.each do |attachment|
            parts << format_input_attachment(attachment)
          end
          parts
        elsif content.is_a?(Content::Raw)
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
        end.join('')
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
```

**Benefits of this approach:**
- **No conditionals** - Each method is pure
- **Clean inheritance** - Overrides only what differs
- **Provider-level config** - No passing through params
- **Testable** - Each provider can be tested independently
- **Follows Ruby conventions** - Inheritance over conditional logic

---

### Phase 3: Testing Strategy

#### 3.1 VCR Cassettes

Create cassettes in `spec/fixtures/vcr_cassettes/openai_responses/`:

- `stateless_single_turn.yml`
- `stateful_multi_turn.yml`
- `tool_calling.yml`
- `response_id_expired.yml`
- `streaming.yml`
- `with_instructions.yml`
- `structured_output.yml`

#### 3.2 Unit Tests

```ruby
# spec/ruby_llm/providers/openai_responses_spec.rb
RSpec.describe RubyLLM::Providers::OpenAIResponses do
  it 'inherits from OpenAI'
  it 'uses responses endpoint'
  it 'uses flat tool format'
  it 'separates instructions from input'
  it 'uses typed content items'
  it 'sends previous_response_id in stateful mode'
  it 'sends full history in stateless mode'
  it 'parses reasoning metadata'
  it 'handles response status'
  it 'recovers from response ID errors'
end

# spec/ruby_llm/chat_spec.rb
RSpec.describe RubyLLM::Chat do
  describe '#with_responses_api' do
    it 'switches to OpenAIResponses provider'
    it 'returns self for chaining'
    it 'passes configuration to provider'
    it 'preserves responses session'
  end

  describe '#responses_api_enabled?' do
    it 'returns true when using OpenAIResponses'
    it 'returns false when using standard OpenAI'
  end
end
```

---

## Files Modified/Added Summary

### New Files

1. **`lib/ruby_llm/responses_session.rb`** - Session state management
2. **`lib/ruby_llm/providers/openai_responses.rb`** - Responses API provider (inherits from OpenAI)

### Modified Files

1. **`lib/ruby_llm/chat.rb`**
   - Add `with_responses_api` method (switches provider)
   - Add `responses_session` accessor
   - Add `restore_responses_session` method
   - Add `responses_api_enabled?` query method
   - Update `complete` to track response_id

2. **`lib/ruby_llm/message.rb`**
   - Add `response_id`, `reasoning_summary`, `reasoning_tokens` attributes
   - Update `to_h`

3. **`lib/ruby_llm/error.rb`**
   - Add Responses API error classes

---

## Migration Path

### For Users

```ruby
# Default behavior unchanged
chat = RubyLLM.chat(model: 'gpt-4o')
response = chat.ask('Hi')
# → Uses v1/chat/completions

# Opt-in to Responses API
chat = RubyLLM.chat(model: 'gpt-4o')
  .with_responses_api
  .ask('Hi')
# → Uses v1/responses (stateless)

# Stateful mode
chat = RubyLLM.chat(model: 'gpt-5-pro')
  .with_responses_api(stateful: true)
response = chat.ask('Hi')
puts response.reasoning_summary
puts response.reasoning_tokens
puts response.response_id

# Persist session for Rails
session_data = chat.responses_session.to_h
# save to database...

# Restore session
chat = RubyLLM.chat(model: 'gpt-5-pro')
  .with_responses_api(stateful: true)
  .restore_responses_session(session_data)
  .ask('Continue')
```

---

## Architecture Diagram

```
┌─────────────────────────────────────────────────┐
│                 RubyLLM::Chat                    │
│  ┌───────────────────────────────────────────┐  │
│  │         ResponsesSession (state)          │  │
│  │  - response_id, last_activity, etc.       │  │
│  └───────────────────────────────────────────┘  │
│                                                 │
│  with_responses_api() → switches @provider      │
│  responses_session → per-conversation state     │
└──────────────────┬──────────────────────────────┘
                   │
        if OpenAI provider, switch to:
                   │
                   ▼
┌─────────────────────────────────────────────────┐
│        RubyLLM::Providers::OpenAIResponses      │
│            (inherits from OpenAI)               │
│                                                 │
│  Overrides (no conditionals):                   │
│  - completion_url → 'responses'                 │
│  - render_payload → instructions + input        │
│  - parse_completion_response → status checking  │
│  - tool_for → flat format                       │
│  - build_chunk → Responses API events           │
│                                                 │
│  @responses_session ← shared with Chat          │
│  @responses_config ← stateful, store, etc.      │
└─────────────────────────────────────────────────┘
                   │
             inherits from
                   │
                   ▼
┌─────────────────────────────────────────────────┐
│          RubyLLM::Providers::OpenAI             │
│  (chat/completions - unchanged)                 │
└─────────────────────────────────────────────────┘
```

---

## Summary of Key Decisions

1. **Separate provider class** - `OpenAIResponses < OpenAI` for clean separation
2. **No conditionals** - Each method is pure, no `if using_responses_api?` checks
3. **Provider switches on opt-in** - Chat creates new provider instance
4. **Session in Chat** - Per-conversation state, shared with provider
5. **Config in provider** - Responses configuration stored in provider instance
6. **Clean inheritance** - Overrides only what differs, inherits everything else
7. **No reflection methods** - Proper initialization with keyword arguments
8. **Backward compatible** - Default behavior unchanged

---

## Implementation Checklist

### Phase 1: Core Infrastructure
- [ ] Add `ResponsesSession` class
- [ ] Extend `Message` with new attributes
- [ ] Add Responses API error classes
- [ ] Add `with_responses_api` to Chat (switches provider)
- [ ] Add `responses_session` to Chat
- [ ] Add `restore_responses_session` to Chat
- [ ] Add `responses_api_enabled?` to Chat
- [ ] Update `Chat#complete` to track response_id

### Phase 2: Provider Class
- [ ] Create `OpenAIResponses` provider (inherits from `OpenAI`)
- [ ] Override `completion_url`
- [ ] Override `complete` with error recovery
- [ ] Override `render_payload` with correct format
- [ ] Override `parse_completion_response` with status checking
- [ ] Override `tool_for` with flat format
- [ ] Override `build_chunk` for streaming
- [ ] Add private helper methods

### Phase 3: Testing & Documentation
- [ ] Create VCR cassettes
- [ ] Write unit tests for OpenAIResponses
- [ ] Write integration tests for Chat
- [ ] Update documentation
- [ ] Add examples to README

---

## Expected Benefits

1. **Clean architecture** - Separate provider class with clear responsibilities
2. **No conditional logic** - Each method does one thing
3. **Easy to test** - Each provider tested independently
4. **Backward compatible** - Default behavior unchanged
5. **Follows Ruby idioms** - Inheritance, proper initialization
6. **No reflection** - Clean keyword argument constructors
7. **Extensible** - Easy to add Responses-specific features
8. **Maintainable** - Clear separation of concerns

This implementation provides native OpenAI Responses API support with a clean, maintainable architecture that follows Ruby best practices.
