---
layout: default
title: Chat
parent: Guides
nav_order: 2
permalink: /guides/chat
---

# Chatting with AI Models

RubyLLM's chat interface provides a natural way to interact with various AI models. This guide covers everything from basic chatting to advanced features like multimodal inputs and streaming responses.

## Basic Chat

Creating a chat and asking questions is straightforward:

```ruby
# Create a chat with the default model
chat = RubyLLM.chat

# Ask a question
response = chat.ask "What's the best way to learn Ruby?"

# The response is a Message object
puts response.content
puts "Role: #{response.role}"
puts "Model: #{response.model_id}"
puts "Tokens: #{response.input_tokens} input, #{response.output_tokens} output"
```

## Choosing Models

You can specify which model to use when creating a chat:

```ruby
# Create a chat with a specific model
chat = RubyLLM.chat(model: 'gpt-4o-mini')

# Use Claude instead
claude_chat = RubyLLM.chat(model: 'claude-3-5-sonnet-20241022')

# Or change the model for an existing chat
chat.with_model('gemini-2.0-flash')
```

## Multi-turn Conversations

Chats maintain conversation history automatically:

```ruby
chat = RubyLLM.chat

# Start a conversation
chat.ask "What's your favorite programming language?"

# Follow up
chat.ask "Why do you like that language?"

# Continue the conversation
chat.ask "What are its weaknesses?"

# Access the conversation history
chat.messages.each do |message|
  puts "#{message.role}: #{message.content[0..50]}..."
end
```

## Working with Images

Vision-capable models can understand images:

```ruby
chat = RubyLLM.chat

# Ask about an image (local file)
chat.ask "What's in this image?", with: { image: "path/to/image.jpg" }

# Or use an image URL
chat.ask "Describe this picture", with: { image: "https://example.com/image.jpg" }

# Include multiple images
chat.ask "Compare these two charts", with: {
  image: ["chart1.png", "chart2.png"]
}

# Combine text and image
chat.ask "Is this the Ruby logo?", with: { image: "logo.png" }
```

## Working with Audio

Models with audio capabilities can process spoken content:

```ruby
chat = RubyLLM.chat(model: 'gpt-4o-audio-preview')

# Analyze audio content
chat.ask "What's being said in this recording?", with: {
  audio: "meeting.wav"
}

# Ask follow-up questions about the audio
chat.ask "Summarize the key points mentioned"
```

## Streaming Responses

For a more interactive experience, you can stream responses as they're generated:

```ruby
chat = RubyLLM.chat

# Stream the response with a block
chat.ask "Tell me a story about a Ruby programmer" do |chunk|
  # Each chunk is a partial response
  print chunk.content
  $stdout.flush # Ensure output is displayed immediately
end

# Useful for long responses or real-time displays
chat.ask "Write a detailed essay about programming paradigms" do |chunk|
  add_to_ui(chunk.content) # Your method to update UI
end
```

## Temperature Control

Control the creativity and randomness of AI responses:

```ruby
# Higher temperature (more creative)
creative_chat = RubyLLM.chat.with_temperature(0.9)
creative_chat.ask "Write a poem about Ruby programming"

# Lower temperature (more deterministic)
precise_chat = RubyLLM.chat.with_temperature(0.1)
precise_chat.ask "Explain how Ruby's garbage collector works"
```

## Access Token Usage

RubyLLM automatically tracks token usage for billing and quota management:

```ruby
chat = RubyLLM.chat
response = chat.ask "Explain quantum computing"

# Check token usage
puts "Input tokens: #{response.input_tokens}"
puts "Output tokens: #{response.output_tokens}"
puts "Total tokens: #{response.input_tokens + response.output_tokens}"

# Estimate cost (varies by model)
model = RubyLLM.models.find(response.model_id)
input_cost = response.input_tokens * model.input_price_per_million / 1_000_000
output_cost = response.output_tokens * model.output_price_per_million / 1_000_000
puts "Estimated cost: $#{(input_cost + output_cost).round(6)}"
```

## Registering Event Handlers

You can register callbacks for chat events:

```ruby
chat = RubyLLM.chat

# Called when a new assistant message starts
chat.on_new_message do
  puts "Assistant is typing..."
end

# Called when a message is complete
chat.on_end_message do |message|
  puts "Response complete!"
  puts "Used #{message.input_tokens + message.output_tokens} tokens"
end

# These callbacks work with both streaming and non-streaming responses
chat.ask "Tell me about Ruby's history"
```

## Multiple Parallel Chats

You can maintain multiple separate chat instances:

```ruby
# Create multiple chat instances
ruby_chat = RubyLLM.chat
python_chat = RubyLLM.chat

# Each has its own conversation history
ruby_chat.ask "What's great about Ruby?"
python_chat.ask "What's great about Python?"

# Continue separate conversations
ruby_chat.ask "How does Ruby handle metaprogramming?"
python_chat.ask "How does Python handle decorators?"
```

## Next Steps

Now that you understand chat basics, you might want to explore:

- [Using Tools]({% link guides/tools.md %}) to let AI use your Ruby code
- [Streaming Responses]({% link guides/streaming.md %}) for real-time interactions
- [Rails Integration]({% link guides/rails.md %}) to persist conversations in your apps