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
  <a href="https://github.com/crmne/ruby_llm/actions/workflows/cicd.yml"><img src="https://github.com/crmne/ruby_llm/actions/workflows/cicd.yml/badge.svg" alt="CI" /></a>
  <a href="https://codecov.io/gh/crmne/ruby_llm"><img src="https://codecov.io/gh/crmne/ruby_llm/branch/main/graph/badge.svg" alt="codecov" /></a>
</p>

🤺 Battle tested at [💬  Chat with Work](https://chatwithwork.com)

---

## Overview

RubyLLM provides a beautiful, unified interface to modern AI services, including:

- 💬 **Chat** with OpenAI GPT, Anthropic Claude, Google Gemini, and DeepSeek models
- 🎵 **Vision and Audio** understanding
- 🖼️ **Image generation** with DALL-E and other providers
- 📊 **Embeddings** for vector search and semantic analysis
- 🔧 **Tools** that let AI use your Ruby code
- 🚂 **Rails integration** to persist chats and messages with ActiveRecord
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
