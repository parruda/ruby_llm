# RubyLLM

A delightful Ruby interface to the latest large language models. Stop wrestling with multiple APIs and inconsistent interfaces. RubyLLM gives you a clean, unified way to work with models from OpenAI, Anthropic, Google, and DeepSeek.

<p align="center">
  <img src="https://upload.wikimedia.org/wikipedia/commons/4/4d/OpenAI_Logo.svg" alt="OpenAI" height="40" width="120">
  &nbsp;&nbsp;&nbsp;&nbsp;
  <img src="https://upload.wikimedia.org/wikipedia/commons/7/78/Anthropic_logo.svg" alt="Anthropic" height="40" width="120">
  &nbsp;&nbsp;&nbsp;&nbsp;
<img src="https://upload.wikimedia.org/wikipedia/commons/8/8a/Google_Gemini_logo.svg" alt="Google" height="40" width="120">
  &nbsp;&nbsp;&nbsp;&nbsp;
  <img src="https://upload.wikimedia.org/wikipedia/commons/e/ec/DeepSeek_logo.svg" alt="DeepSeek" height="40" width="120"]>
</p>

[![Gem Version](https://badge.fury.io/rb/ruby_llm.svg)](https://badge.fury.io/rb/ruby_llm)
[![Ruby Style Guide](https://img.shields.io/badge/code_style-standard-brightgreen.svg)](https://github.com/testdouble/standard)

## Installation

Add it to your Gemfile:

```ruby
gem 'ruby_llm'
```

Or install it yourself:

```bash
gem install ruby_llm
```

## Configuration

```ruby
require 'ruby_llm'

# Configure your API keys
RubyLLM.configure do |config|
  config.openai_api_key = ENV['OPENAI_API_KEY']
  config.anthropic_api_key = ENV['ANTHROPIC_API_KEY']
  config.gemini_api_key = ENV['GEMINI_API_KEY']
  config.deepseek_api_key = ENV['DEEPSEEK_API_KEY']
end
```

## Quick Start

RubyLLM makes it dead simple to start chatting with AI models:

```ruby
# Start a conversation
chat = RubyLLM.chat
chat.ask "What's the best way to learn Ruby?"
```

## Available Models

RubyLLM gives you access to the latest models from multiple providers:

```ruby
# List all available models
RubyLLM.models.all

# Get models by type
chat_models = RubyLLM.models.chat_models
embedding_models = RubyLLM.models.embedding_models
audio_models = RubyLLM.models.audio_models
image_models = RubyLLM.models.image_models
```

## Having a Conversation

Conversations are simple and natural:

```ruby
chat = RubyLLM.chat model: 'claude-3-opus-20240229'

# Ask questions
response = chat.ask "What's your favorite Ruby feature?"

# Multi-turn conversations just work
chat.ask "Can you elaborate on that?"
chat.ask "How does that compare to Python?"

# Stream responses as they come
chat.ask "Tell me a story about a Ruby programmer" do |chunk|
  print chunk.content
end

# Check token usage
last_message = chat.messages.last
puts "Conversation used #{last_message.input_tokens} input tokens and #{last_message.output_tokens} output tokens"
```

## Text Embeddings

Need vector embeddings for your text? RubyLLM makes it simple:

```ruby
# Get embeddings with the default model
RubyLLM.embed "Hello, world!"

# Use a specific model
RubyLLM.embed "Ruby is awesome!", model: "text-embedding-3-large"

# Process multiple texts at once
RubyLLM.embed([
  "First document",
  "Second document",
  "Third document"
])

# Configure the default model
RubyLLM.configure do |config|
  config.default_embedding_model = 'text-embedding-3-large'
end
```

## Using Tools

Give your AI assistants access to your Ruby code by creating tool classes that do one thing well:

```ruby
class Calculator < RubyLLM::Tool
  description "Performs arithmetic calculations"

  param :expression,
    type: :string,
    desc: "A mathematical expression to evaluate (e.g. '2 + 2')"

  def execute(expression:)
    eval(expression).to_s
  end
end

class Search < RubyLLM::Tool
  description "Searches documents by similarity"

  param :query,
    desc: "The search query"

  param :limit,
    type: :integer,
    desc: "Number of results to return",
    required: false

  def initialize(repo:)
    @repo = repo
  end

  def execute(query:, limit: 5)
    @repo.similarity_search(query, limit:)
  end
end
```

Then use them in your conversations:

```ruby
# Simple tools just work
chat = RubyLLM.chat.with_tool Calculator

# Tools with dependencies are just regular Ruby objects
search = Search.new repo: Document
chat.with_tools search, Calculator

# Configure as needed
chat.with_model('claude-3-opus-20240229')
    .with_temperature(0.9)

chat.ask "What's 2+2?"
# => "Let me calculate that for you. The result is 4."

chat.ask "Find documents about Ruby performance"
# => "I found these relevant documents about Ruby performance..."
```

Need to debug a tool? RubyLLM automatically logs all tool calls:

```ruby
ENV['RUBY_LLM_DEBUG'] = 'true'

chat.ask "What's 123 * 456?"
# D, -- RubyLLM: Tool calculator called with: {"expression" => "123 * 456"}
# D, -- RubyLLM: Tool calculator returned: "56088"
```

## Error Handling

RubyLLM wraps provider errors in clear Ruby exceptions:

```ruby
begin
  chat = RubyLLM.chat
  chat.ask "Hello world!"
rescue RubyLLM::UnauthorizedError
  puts "Check your API credentials"
rescue RubyLLM::BadRequestError => e
  puts "Something went wrong: #{e.message}"
rescue RubyLLM::PaymentRequiredError
  puts "Time to top up your API credits"
rescue RubyLLM::ServiceUnavailableError
  puts "API service is temporarily down"
end
```

## Rails Integration

RubyLLM comes with built-in Rails support that makes it dead simple to persist your chats and messages. Just create your tables and hook it up:

```ruby
# db/migrate/YYYYMMDDHHMMSS_create_chats.rb
class CreateChats < ActiveRecord::Migration[8.0]
  def change
    create_table :chats do |t|
      t.string :model_id
      t.timestamps
    end
  end
end

# db/migrate/YYYYMMDDHHMMSS_create_messages.rb
class CreateMessages < ActiveRecord::Migration[8.0]
  def change
    create_table :messages do |t|
      t.references :chat, null: false
      t.string :role
      t.text :content
      t.string :model_id
      t.integer :input_tokens
      t.integer :output_tokens
      t.references :tool_call
      t.timestamps
    end
  end
end

# db/migrate/YYYYMMDDHHMMSS_create_tool_calls.rb
class CreateToolCalls < ActiveRecord::Migration[8.0]
  def change
    create_table :tool_calls do |t|
      t.references :message, null: false
      t.string :tool_call_id, null: false
      t.string :name, null: false
      t.jsonb :arguments, default: {}
      t.timestamps
    end

    add_index :tool_calls, :tool_call_id
  end
end
```

Then in your models:

```ruby
class Chat < ApplicationRecord
  acts_as_chat

  # Optional: Add Turbo Streams support
  broadcasts_to ->(chat) { "chat_#{chat.id}" }
end

class Message < ApplicationRecord
  acts_as_message
end

class ToolCall < ApplicationRecord
  acts_as_tool_call
end
```

That's it! Now you can use chats straight from your models:

```ruby
# Create a new chat
chat = Chat.create! model_id: "gpt-4o-mini"

# Ask questions - messages are automatically saved
chat.ask "What's the weather in Paris?"

# Stream responses in real-time
chat.ask "Tell me a story" do |chunk|
  broadcast_chunk chunk
end

# Everything is persisted automatically
chat.messages.each do |message|
  case message.role
  when :user
    puts "User: #{message.content}"
  when :assistant
    puts "Assistant: #{message.content}"
  end
end
```

### Real-time Updates with Hotwire

The Rails integration works great with Hotwire out of the box:

```ruby
# app/controllers/chats_controller.rb
class ChatsController < ApplicationController
  def show
    @chat = Chat.find(params[:id])
  end

  def ask
    @chat = Chat.find(params[:id])
    @chat.ask(params[:message]) do |chunk|
      Turbo::StreamsChannel.broadcast_append_to(
        @chat,
        target: "messages",
        partial: "messages/chunk",
        locals: { chunk: chunk }
      )
    end
  end
end

# app/views/chats/show.html.erb
<%= turbo_stream_from @chat %>

<div id="messages">
  <%= render @chat.messages %>
</div>

<%= form_with(url: ask_chat_path(@chat), local: false) do |f| %>
  <%= f.text_area :message %>
  <%= f.submit "Send" %>
<% end %>
```

### Background Jobs

The persistence works seamlessly with background jobs:

```ruby
class ChatJob < ApplicationJob
  def perform(chat_id, message)
    chat = Chat.find chat_id

    chat.ask(message) do |chunk|
      # Optional: Broadcast chunks for real-time updates
      Turbo::StreamsChannel.broadcast_append_to(
        chat,
        target: "messages",
        partial: "messages/chunk",
        locals: { chunk: chunk }
      )
    end
  end
end
```

### Using Tools

Tools work just like they do in regular RubyLLM chats:

```ruby
class WeatherTool < RubyLLM::Tool
  description "Gets current weather for a location"

  param :location,
    type: :string,
    desc: "City name or coordinates"

  def execute(location:)
    # Fetch weather data...
    { temperature: 22, conditions: "Sunny" }
  end
end

# Use tools with your persisted chats
chat = Chat.create! model_id: "gpt-4"
chat.chat.with_tool WeatherTool.new

# Ask about weather - tool usage is automatically saved
chat.ask "What's the weather in Paris?"

# Tool calls and results are persisted as messages
pp chat.messages.map(&:role)
#=> [:user, :assistant, :tool, :assistant]
```

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `bin/console` for an interactive prompt.

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/crmne/ruby_llm.

## License

Released under the MIT License. See [LICENSE](LICENSE) for details.