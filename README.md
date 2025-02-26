# RubyLLM

A delightful Ruby way to work with AI. Chat in text, analyze and generate images, understand audio, and use tools through a unified interface to OpenAI, Anthropic, Google, and DeepSeek. Built for developer happiness with automatic token counting, proper streaming, and Rails integration. No wrapping your head around multiple APIs - just clean Ruby code that works.

<p align="center">
  <img src="https://upload.wikimedia.org/wikipedia/commons/4/4d/OpenAI_Logo.svg" alt="OpenAI" height="40" width="120">
  &nbsp;&nbsp;&nbsp;&nbsp;
  <img src="https://upload.wikimedia.org/wikipedia/commons/7/78/Anthropic_logo.svg" alt="Anthropic" height="40" width="120">
  &nbsp;&nbsp;&nbsp;&nbsp;
  <img src="https://upload.wikimedia.org/wikipedia/commons/8/8a/Google_Gemini_logo.svg" alt="Google" height="40" width="120">
  &nbsp;&nbsp;&nbsp;&nbsp;
  <img src="https://upload.wikimedia.org/wikipedia/commons/e/ec/DeepSeek_logo.svg" alt="DeepSeek" height="40" width="120">
</p>

<p align="center">
  <a href="https://badge.fury.io/rb/ruby_llm"><img src="https://badge.fury.io/rb/ruby_llm.svg" alt="Gem Version" /></a>
  <a href="https://github.com/testdouble/standard"><img src="https://img.shields.io/badge/code_style-standard-brightgreen.svg" alt="Ruby Style Guide" /></a>
  <a href="https://rubygems.org/gems/ruby_llm"><img alt="Gem Total Downloads" src="https://img.shields.io/gem/dt/ruby_llm"></a>
  <a href="https://codecov.io/gh/crmne/ruby_llm"><img src="https://codecov.io/gh/crmne/ruby_llm/branch/main/graph/badge.svg" alt="codecov" /></a>
</p>

🤺 Battle tested at [💬  Chat with Work](https://chatwithwork.com)

## Features

- 💬 **Beautiful Chat Interface** - Converse with AI models as easily as `RubyLLM.chat.ask "teach me Ruby"`
- 🎵 **Audio Analysis** - Get audio transcription and understanding with `chat.ask "what's said here?", with: { audio: "clip.wav" }`
- 👁️ **Vision Understanding** - Let AIs analyze images with a simple `chat.ask "what's in this?", with: { image: "photo.jpg" }`
- 🌊 **Streaming** - Real-time responses with proper Ruby streaming with `chat.ask "hello" do |chunk| puts chunk.content end`
- 📄 **PDF Analysis** - Analyze PDF documents directly with `chat.ask "What's in this?", with: { pdf: "document.pdf" }`
- 🚂 **Rails Integration** - Persist chats and messages with ActiveRecord with `acts_as_{chat|message|tool_call}`
- 🛠️ **Tool Support** - Give AIs access to your Ruby code with `chat.with_tool(Calculator).ask "what's 2+2?"`
- 🎨 **Paint with AI** - Create images as easily as `RubyLLM.paint "a sunset over mountains"`
- 📊 **Embeddings** - Generate vector embeddings for your text with `RubyLLM.embed "hello"`
- 🔄 **Multi-Provider Support** - Works with OpenAI, Anthropic, Google, and DeepSeek
- 🎯 **Token Tracking** - Automatic usage tracking across providers

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

## Full documentation

Comprehensive guides are available at https://rubyllm.com/

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
chat = RubyLLM.chat model: 'gemini-2.0-flash'

# Ask questions
response = chat.ask "What's your favorite Ruby feature?"

# Multi-turn conversations just work
chat.ask "Can you elaborate on that?"
chat.ask "How does that compare to Python?"

# Stream responses as they come
chat.ask "Tell me a story about a Ruby programmer" do |chunk|
  print chunk.content
end

# Ask about images
chat.ask "What do you see in this image?", with: { image: "ruby_logo.png" }

# Get analysis of audio content
chat.ask "What's being said in this recording?", with: { audio: "meeting.wav" }

# Combine multiple pieces of content
chat.ask "Compare these diagrams", with: { image: ["diagram1.png", "diagram2.png"] }

# Ask about PDFs

chat = RubyLLM.chat(model: 'claude-3-7-sonnet-20250219')
chat.ask "Summarize this research paper", with: { pdf: "research.pdf" }

# Multiple PDFs work too
chat.ask "Compare these contracts", with: { pdf: ["contract1.pdf", "contract2.pdf"] }

# Check token usage
last_message = chat.messages.last
puts "Conversation used #{last_message.input_tokens} input tokens and #{last_message.output_tokens} output tokens"
```

You can provide content as local files or URLs - RubyLLM handles the rest. Vision and audio capabilities are available with compatible models. The API stays clean and consistent whether you're working with text, images, or audio.

## Image Generation

Want to create AI-generated images? RubyLLM makes it super simple:

```ruby
# Paint a picture!
image = RubyLLM.paint "a starry night over San Francisco in Van Gogh's style"
image.url         # => "https://..."
image.revised_prompt  # Shows how DALL-E interpreted your prompt

# Choose size and model
image = RubyLLM.paint(
  "a cyberpunk cityscape at sunset",
  model: "dall-e-3",
  size: "1792x1024"
)

# Set your default model
RubyLLM.configure do |config|
  config.default_image_model = "dall-e-3"
end
```

RubyLLM automatically handles all the complexities of the DALL-E API, token/credit management, and error handling, so you can focus on being creative.

## Text Embeddings

Need vector embeddings for your text? RubyLLM makes it simple:

```ruby
# Get embeddings with the default model
RubyLLM.embed "Hello, world!"

# Use a specific model
RubyLLM.embed "Ruby is awesome!", model: "text-embedding-004"

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
chat.with_model('claude-3-5-sonnet-20241022')
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
chat = Chat.create! model_id: "deepseek-reasoner"
chat.chat.with_tool WeatherTool.new

# Ask about weather - tool usage is automatically saved
chat.ask "What's the weather in Paris?"

# Tool calls and results are persisted as messages
pp chat.messages.map(&:role)
#=> [:user, :assistant, :tool, :assistant]
```

## Provider Comparison

| Feature | OpenAI | Anthropic | Google | DeepSeek |
|---------|--------|-----------|--------|----------|
| Chat | ✅ GPT-4o, GPT-3.5 | ✅ Claude 3.7, 3.5, 3 | ✅ Gemini 2.0, 1.5 | ✅ DeepSeek Chat, Reasoner |
| Vision | ✅ GPT-4o, GPT-4 | ✅ All Claude 3 models | ✅ Gemini 2.0, 1.5 | ❌ |
| Audio | ✅ GPT-4o-audio, Whisper | ❌ | ✅ Gemini models | ❌ |
| PDF Analysis | ❌ | ✅ All Claude 3 models | ✅ Gemini models | ❌ |
| Function Calling | ✅ Most models | ✅ Claude 3 models | ✅ Gemini models (except Lite) | ✅ |
| JSON Mode | ✅ Most recent models | ✅ Claude 3 models | ✅ Gemini models | ❌ |
| Image Generation | ✅ DALL-E 3 | ❌ | ✅ Imagen | ❌ |
| Embeddings | ✅ text-embedding-3 | ❌ | ✅ text-embedding-004 | ❌ |
| Context Size | ⭐ Up to 200K (o1) | ⭐ 200K tokens | ⭐ Up to 2M tokens | 64K tokens |
| Streaming | ✅ | ✅ | ✅ | ✅ |

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `bin/console` for an interactive prompt.

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/crmne/ruby_llm.

## License

Released under the MIT License. See [LICENSE](LICENSE) for details.