---
layout: default
title: Home
nav_order: 1
description: "RubyLLM is a delightful Ruby way to work with AI."
permalink: /
---

# RubyLLM
{: .fs-9 }

A delightful Ruby way to work with AI through a unified interface to OpenAI, Anthropic, Google, and DeepSeek.
{: .fs-6 .fw-300 }

[Get started now]({% link installation.md %}){: .btn .btn-primary .fs-5 .mb-4 .mb-md-0 .mr-2 }
[View on GitHub](https://github.com/crmne/ruby_llm){: .btn .fs-5 .mb-4 .mb-md-0 }

---

## Overview

RubyLLM provides a beautiful, unified interface to modern AI services, including:

- 💬 **Chat** with OpenAI GPT, Anthropic Claude, Google Gemini, and DeepSeek models
- 🖼️ **Image generation** with DALL-E and other providers
- 🔍 **Embeddings** for vector search and semantic analysis
- 🔧 **Tools** that let AI use your Ruby code
- 🚊 **Rails integration** to persist chats and messages with ActiveRecord
- 🌊 **Streaming** responses with proper Ruby patterns

## Quick start

```ruby
require 'ruby_llm'

# Configure your API keys
RubyLLM.configure do |config|
  config.openai_api_key = ENV['OPENAI_API_KEY']
end

# Start chatting
chat = RubyLLM.chat
response = chat.ask "What's the best way to learn Ruby?"

# Generate images
image = RubyLLM.paint "a sunset over mountains"
puts image.url
```

## Learn more

- [Installation]({% link installation.md %})
- [Guides]({% link guides/index.md %})
