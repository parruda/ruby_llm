# RubyLLM

The Ruby library for working with Large Language Models (LLMs).

[![Gem Version](https://badge.fury.io/rb/ruby_llm.svg)](https://badge.fury.io/rb/ruby_llm)
[![Ruby Style Guide](https://img.shields.io/badge/code_style-standard-brightgreen.svg)](https://github.com/testdouble/standard)

RubyLLM provides a unified interface for interacting with various LLM providers including OpenAI, Anthropic, and more. It offers both standalone usage and seamless Rails integration.

## Features

- 🤝 Unified interface for multiple LLM providers (OpenAI, Anthropic, etc.)
- 🛠️ Tool/Function calling support
- 📊 Automatic token counting and tracking
- 🔄 Streaming support
- 🚂 Seamless Rails integration

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'ruby_llm'
```

And then execute:
```bash
$ bundle install
```

Or install it directly:

```bash
$ gem install ruby_llm
```

## Usage

### Basic Setup

```ruby
require 'ruby_llm'

RubyLLM.configure do |config|
  config.openai_api_key = ENV['OPENAI_API_KEY']
  config.anthropic_api_key = ENV['ANTHROPIC_API_KEY']
  config.default_model = 'gpt-4'
end
```

### Simple Chat

```ruby
client = RubyLLM.client

response = client.chat([
  { role: :user, content: "Hello!" }
])

puts response.content
```

### Streaming

```ruby
client.chat([
  { role: :user, content: "Count to 10 slowly" }
], stream: true) do |chunk|
  print chunk.content
end
```

### Tool Usage

```ruby
calculator = RubyLLM::Tool.new(
  name: "calculator",
  description: "Perform mathematical calculations",
  parameters: {
    expression: {
      type: "string",
      description: "The mathematical expression to evaluate",
      required: true
    }
  }
) do |args|
  eval(args[:expression]).to_s
end

response = client.chat([
  { role: :user, content: "What is 123 * 456?" }
], tools: [calculator])
```

## Rails Integration

RubyLLM provides seamless Rails integration with Active Record models.

### Configuration

Create an initializer `config/initializers/ruby_llm.rb`:

```ruby
RubyLLM.configure do |config|
  config.openai_api_key = Rails.application.credentials.openai[:api_key]
  config.anthropic_api_key = Rails.application.credentials.anthropic[:api_key]
  config.default_model = Rails.env.production? ? 'gpt-4' : 'gpt-3.5-turbo'
end
```

### Models

```ruby
# app/models/llm_model.rb
class LLMModel < ApplicationRecord
  acts_as_llm_model

  # Schema:
  #  t.string :provider
  #  t.string :name
  #  t.jsonb :capabilities
  #  t.integer :context_length
  #  t.timestamps
end

# app/models/conversation.rb
class Conversation < ApplicationRecord
  acts_as_llm_conversation
  belongs_to :user

  # Schema:
  #  t.references :user
  #  t.string :title
  #  t.string :current_model
  #  t.timestamps
end

# app/models/message.rb
class Message < ApplicationRecord
  acts_as_llm_message

  # Schema:
  #  t.references :conversation
  #  t.string :role
  #  t.text :content
  #  t.jsonb :tool_calls
  #  t.jsonb :tool_results
  #  t.integer :token_count
  #  t.timestamps
end
```

### Controller Usage

```ruby
class ConversationsController < ApplicationController
  def create
    @conversation = current_user.conversations.create!
    redirect_to @conversation
  end

  def send_message
    @conversation = current_user.conversations.find(params[:id])

    message = @conversation.send_message(
      params[:content],
      model: params[:model]
    )

    render json: message
  end
end
```

## Development

After checking out the repo, run `bin/setup` to install dependencies. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`.

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/crmne/ruby_llm.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).