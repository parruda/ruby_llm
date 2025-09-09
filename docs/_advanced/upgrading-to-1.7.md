---
layout: default
title: Upgrading to 1.7
nav_order: 6
description: Upgrade to the DB-backed model registry for better data integrity and rich model metadata.
---

# {{ page.title }}
{: .no_toc }

{{ page.description }}
{: .fs-6 .fw-300 }

## Table of contents
{: .no_toc .text-delta }

1. TOC
{:toc}

---

## What's New in 1.7

Among other features, the DB-backed model registry replaces simple string fields with proper ActiveRecord associations. Additionally, the `acts_as` helpers have been redesigned with a more Rails-like API.

### Available with DB-backed Model Registry
{: .d-inline-block }

v1.7.0+
{: .label .label-green }

**New Rails-like `acts_as` API**
```ruby
# New API uses association names as primary parameters
acts_as_chat messages: :messages, model: :model
acts_as_message chat: :chat, tool_calls: :tool_calls

# vs Legacy API which required explicit class names
acts_as_chat message_class: 'Message', tool_call_class: 'ToolCall'
acts_as_message chat_class: 'Chat', chat_foreign_key: 'chat_id'
```

**Rich model metadata**
```ruby
chat.model.name              # => "GPT-4"
chat.model.context_window    # => 128000
chat.model.supports_vision   # => true
chat.model.input_token_cost  # => 2.50
```

**Provider routing**
```ruby
Chat.create!(model: "{{ site.models.anthropic_current }}", provider: "bedrock")
```

**Model associations and queries**
```ruby
Chat.joins(:model).where(models: { provider: 'anthropic' })
Model.select { |m| m.supports_functions? }  # Use delegated methods
```

**Model alias resolution**
```ruby
Chat.create!(model: "{{ site.models.default_chat }}", provider: "openrouter")  # Resolves to openai/{{ site.models.default_chat }} automatically
```

**Usage tracking**
```ruby
Model.joins(:chats).group(:id).order('COUNT(chats.id) DESC')
```

### Available without Model Registry
{: .d-inline-block }

Legacy mode
{: .label .label-yellow }

**Legacy `acts_as` API** - Still uses the old parameter style
```ruby
acts_as_chat message_class: 'Message', tool_call_class: 'ToolCall'
acts_as_message chat_class: 'Chat', tool_call_class: 'ToolCall'
```

**Basic functionality** - All core RubyLLM features work
```ruby
chat.ask("Hello!")  # Works fine
chat.model_id  # => "{{ site.models.openai_standard }}" (string only, no metadata)
```

**Limited to:**
- String-based model IDs only
- Default provider routing

## Upgrading from 1.6

### Your App Continues Working

Your existing 1.6 app continues working without any changes (legacy API is the default). You'll see a deprecation warning on Rails boot:

```
RubyLLM: Legacy acts_as API is deprecated and will be removed in RubyLLM 2.0.0.
Please migrate to the new association-based API.
```

### Migrate to Model Registry (Recommended)

```bash
rails generate ruby_llm:install
rails generate ruby_llm:migrate_model_fields
rails db:migrate
```

Then opt into the new API in your initializer:

```ruby
# config/initializers/ruby_llm.rb
RubyLLM.configure do |config|
  config.use_new_acts_as = true  # Use the new API!
end
```

That's it! The migration:
- Creates the models table
- Loads all models from models.json automatically
- Migrates your existing data to use foreign keys
- Preserves everything (renames old columns to `model_id_string`)
- Enables the new `acts_as` API (when you set `use_new_acts_as = true`)

> **Note:** Legacy API is the default for backward compatibility. Set `config.use_new_acts_as = true` to use the new API!
{: .info }

### If You Have Custom Model Names

If you're using custom model names (e.g., `Conversation` instead of `Chat`), you may need to update your `acts_as` declarations to the new API:

**Before (1.6):**
```ruby
class Conversation < ApplicationRecord
  acts_as_chat message_class: 'ChatMessage', tool_call_class: 'AIToolCall'
end

class ChatMessage < ApplicationRecord
  acts_as_message chat_class: 'Conversation', chat_foreign_key: 'conversation_id'
end
```

**After (1.7):**
```ruby
class Conversation < ApplicationRecord
  acts_as_chat messages: :chat_messages,  # Association name
               message_class: 'ChatMessage'  # Class name if not inferrable
end

class ChatMessage < ApplicationRecord
  acts_as_message chat: :conversation,  # Association name
                  chat_class: 'Conversation'  # Class name if not inferrable
end
```

## New Applications

Fresh installs get the model registry automatically:

```bash
rails generate ruby_llm:install
rails db:migrate
```
