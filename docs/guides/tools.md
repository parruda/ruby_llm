---
layout: default
title: Tools
parent: Guides
nav_order: 3
permalink: /guides/tools
---

# Using Tools with RubyLLM

Tools allow AI models to call your Ruby code to perform actions or retrieve information. This guide explains how to create and use tools with RubyLLM.

## What Are Tools?

Tools (also known as "functions" or "plugins") let AI models:

1. Recognize when external functionality is needed
2. Call your Ruby code with appropriate parameters
3. Use the results to enhance their responses

Common use cases include:
- Retrieving real-time data
- Performing calculations
- Accessing databases
- Controlling external systems

## Creating a Tool

Tools are defined as Ruby classes that inherit from `RubyLLM::Tool`:

```ruby
class Calculator < RubyLLM::Tool
  description "Performs arithmetic calculations"

  param :expression,
    type: :string,
    desc: "A mathematical expression to evaluate (e.g. '2 + 2')"

  def execute(expression:)
    eval(expression).to_s
  rescue StandardError => e
    "Error: #{e.message}"
  end
end
```

### Tool Components

Each tool has these key elements:

1. **Description** - Explains what the tool does, helping the AI decide when to use it
2. **Parameters** - Define the inputs the tool expects
3. **Execute Method** - The code that runs when the tool is called

### Parameter Definition

Parameters accept several options:

```ruby
param :parameter_name,
  type: :string,          # Data type (:string, :integer, :boolean, :array, :object)
  desc: "Description",    # Description of what the parameter does
  required: true          # Whether the parameter is required (default: true)
```

## Using Tools in Chat

To use a tool, attach it to a chat:

```ruby
# Create the chat
chat = RubyLLM.chat

# Add a tool
chat.with_tool(Calculator)

# Now you can ask questions that might require calculation
response = chat.ask "What's 123 * 456?"
# => "Let me calculate that for you. 123 * 456 = 56088."
```

### Multiple Tools

You can provide multiple tools to a single chat:

```ruby
class Weather < RubyLLM::Tool
  description "Gets current weather for a location"

  param :location,
    desc: "City name or zip code"

  def execute(location:)
    # Simulate weather lookup
    "72°F and sunny in #{location}"
  end
end

# Add multiple tools
chat = RubyLLM.chat
  .with_tools(Calculator, Weather)

# Ask questions that might use either tool
chat.ask "What's the temperature in New York City?"
chat.ask "If it's 72°F in NYC and 54°F in Boston, what's the average?"
```

## Custom Initialization

Tools can have custom initialization:

```ruby
class DocumentSearch < RubyLLM::Tool
  description "Searches documents by relevance"

  param :query,
    desc: "The search query"

  param :limit,
    type: :integer,
    desc: "Maximum number of results",
    required: false

  def initialize(database)
    @database = database
  end

  def execute(query:, limit: 5)
    # Search in @database
    @database.search(query, limit: limit)
  end
end

# Initialize with dependencies
search_tool = DocumentSearch.new(MyDatabase)
chat.with_tool(search_tool)
```

## The Tool Execution Flow

Here's what happens when a tool is used:

1. You ask a question
2. The model decides a tool is needed
3. The model selects the tool and provides arguments
4. RubyLLM calls your tool's `execute` method
5. The result is sent back to the model
6. The model incorporates the result into its response

For example:

```ruby
response = chat.ask "What's 123 squared plus 456?"

# Behind the scenes:
# 1. Model decides it needs to calculate
# 2. Model calls Calculator with expression: "123 * 123 + 456"
# 3. Tool returns "15,585"
# 4. Model incorporates this in its response
```

## Debugging Tools

Enable debugging to see tool calls in action:

```ruby
# Enable debug logging
ENV['RUBYLLM_DEBUG'] = 'true'

# Make a request
chat.ask "What's 15329 divided by 437?"

# Console output:
# D, -- RubyLLM: Tool calculator called with: {"expression"=>"15329 / 437"}
# D, -- RubyLLM: Tool calculator returned: "35.078719"
```

## Error Handling

Tools can handle errors gracefully:

```ruby
class Calculator < RubyLLM::Tool
  description "Performs arithmetic calculations"

  param :expression,
    type: :string,
    desc: "Math expression to evaluate"

  def execute(expression:)
    eval(expression).to_s
  rescue StandardError => e
    # Return error as a result
    { error: "Error calculating #{expression}: #{e.message}" }
  end
end

# When there's an error, the model will receive and explain it
chat.ask "What's 1/0?"
# => "I tried to calculate 1/0, but there was an error: divided by 0"
```

## Advanced Tool Parameters

Tools can have complex parameter types:

```ruby
class DataAnalysis < RubyLLM::Tool
  description "Analyzes numerical data"

  param :data,
    type: :array,
    desc: "Array of numbers to analyze"

  param :operations,
    type: :object,
    desc: "Analysis operations to perform",
    required: false

  def execute(data:, operations: {mean: true, median: false})
    result = {}

    result[:mean] = data.sum.to_f / data.size if operations[:mean]
    result[:median] = calculate_median(data) if operations[:median]

    result
  end

  private

  def calculate_median(data)
    sorted = data.sort
    mid = sorted.size / 2
    sorted.size.odd? ? sorted[mid] : (sorted[mid-1] + sorted[mid]) / 2.0
  end
end
```

## When to Use Tools

Tools are best for:

1. **External data retrieval** - Getting real-time information like weather, prices, or database records
2. **Computation** - When calculations are complex or involve large numbers
3. **System integration** - Connecting to external APIs or services
4. **Data processing** - Working with files, formatting data, or analyzing information
5. **Stateful operations** - When you need to maintain state between calls