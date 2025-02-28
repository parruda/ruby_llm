---
layout: default
title: Image Generation
parent: Guides
nav_order: 6
permalink: /guides/image-generation
---

# Image Generation

RubyLLM makes it easy to generate images using AI models like DALL-E. This guide explains how to create images and customize the generation process.

## Basic Image Generation

The simplest way to generate an image is using the global `paint` method:

```ruby
# Generate an image with DALL-E
image = RubyLLM.paint("a sunset over mountains")

# The URL where you can view/download the image
puts image.url  # => "https://..."

# How the model interpreted your prompt
puts image.revised_prompt  # => "A breathtaking sunset painting the sky with warm..."
```

The `paint` method handles all the complexities of connecting to the right provider and processing the request.

## Choosing Models

By default, RubyLLM uses DALL-E 3, but you can specify a different model:

```ruby
# Use Gemini's Imagen 3 (see details below)
image = RubyLLM.paint(
  "a cyberpunk city at night",
  model: "imagen-3.0-generate-002"
)
```

You can configure the default model globally:

```ruby
RubyLLM.configure do |config|
  config.default_image_model = "dall-e-3"
end
```

## Image Sizes

You can control the size of the generated image:

```ruby
# Standard size (1024x1024)
image = RubyLLM.paint("a white siamese cat")

# Landscape (1792x1024)
landscape = RubyLLM.paint(
  "a panoramic mountain landscape",
  size: "1792x1024"
)

# Portrait (1024x1792)
portrait = RubyLLM.paint(
  "a tall redwood tree",
  size: "1024x1792"
)

# Square with custom size
square = RubyLLM.paint(
  "a perfect square mandala",
  size: "1024x1024" # standard square
)
```

Available sizes depend on the model. DALL-E 3 supports:
- `"1024x1024"` - Standard square (default)
- `"1792x1024"` - Wide landscape
- `"1024x1792"` - Tall portrait

## Working with Generated Images

The `Image` object returned by `paint` contains information about the generated image:

```ruby
image = RubyLLM.paint("a cyberpunk cityscape")

# For url-based images (like DALL-E)
if image.url && !image.base64?
  puts "Image URL: #{image.url}"
end

# For base64 images (like Gemini's Imagen)
if image.base64?
  puts "MIME type: #{image.mime_type}"
  puts "Base64 data available"
end

# How the model interpreted/enhanced your prompt
enhanced_prompt = image.revised_prompt

# The model used to generate the image
model_used = image.model_id
```

### Saving Images Locally

To save the generated image to a local file (works with both URL and base64 images):

```ruby
# Generate an image
image = RubyLLM.paint("a sunset over mountains")

# Save to a file - works with both URL and base64 images
image.save("sunset.png")
```

### Rails Active Storage Integration

The `to_blob` method makes it easy to integrate with Rails' Active Storage:

```ruby
# In a Rails controller or job
def generate_image_for_product(product, prompt)
  # Generate the image with RubyLLM
  image = RubyLLM.paint(prompt)

  # Create a filename based on product and timestamp
  filename = "#{product.slug}-#{Time.current.to_i}.png"

  # Attach the image directly to the product using Active Storage
  product.image.attach(
    io: StringIO.new(image.to_blob),
    filename: filename,
    content_type: image.mime_type || 'image/png'
  )

  # You could also record the generation prompt, model, etc.
  product.update(
    image_prompt: prompt,
    image_revised_prompt: image.revised_prompt,
    image_model: image.model_id
  )
end
```

## Prompt Engineering for Images

Crafting effective prompts is crucial for getting the best results:

```ruby
# Basic prompt
image = RubyLLM.paint("cat")

# Detailed prompt
image = RubyLLM.paint(
  "A fluffy orange tabby cat sitting on a windowsill, " \
  "looking out at a rainy day. Soft lighting, detailed fur, " \
  "photorealistic style."
)
```

### Tips for Better Prompts

1. **Be specific** about subject, setting, lighting, style, and perspective
2. **Specify artistic style** (e.g., "oil painting", "digital art", "photorealistic")
3. **Include lighting details** ("soft morning light", "dramatic sunset")
4. **Add composition details** ("close-up", "wide angle", "overhead view")
5. **Specify mood or atmosphere** ("serene", "mysterious", "cheerful")

## Error Handling

Handle errors that may occur during image generation:

```ruby
begin
  image = RubyLLM.paint("a sunset over mountains")
  puts "Image generated: #{image.url}"
rescue RubyLLM::UnauthorizedError
  puts "Please check your API key"
rescue RubyLLM::BadRequestError => e
  puts "Invalid request: #{e.message}"
rescue RubyLLM::Error => e
  puts "Error generating image: #{e.message}"
end
```

Common errors include:
- `UnauthorizedError` - Invalid API key
- `BadRequestError` - Content policy violation
- `RateLimitError` - Too many requests
- `ServiceUnavailableError` - Service temporarily unavailable

## Content Safety

Image generation models have built-in safety filters. If your prompt violates content policies, you'll receive an error.

To avoid content policy violations:
- Avoid requesting violent, adult, or disturbing content
- Don't ask for images of real public figures
- Avoid copyrighted characters and content
- Be mindful of sensitive subject matter

## Performance Considerations

Image generation typically takes 5-15 seconds. Consider these best practices:

1. **Handle asynchronously** - Don't block your application while waiting
2. **Implement timeouts** - Set appropriate request timeouts
3. **Cache results** - Save images to your server rather than regenerating
4. **Implement retries** - Retry on temporary failures

## Rails Integration

In a Rails application, you might implement image generation like this:

```ruby
class ImagesController < ApplicationController
  def create
    GenerateImageJob.perform_later(
      prompt: params[:prompt],
      user_id: current_user.id
    )

    redirect_to images_path, notice: "Your image is being generated..."
  end
end

class GenerateImageJob < ApplicationJob
  queue_as :default

  def perform(prompt:, user_id:)
    user = User.find(user_id)

    begin
      image = RubyLLM.paint(prompt)

      # Download and store the image
      image_file = URI.open(image.url)

      # Create record in your database
      user.images.create!(
        prompt: prompt,
        revised_prompt: image.revised_prompt,
        file: image_file,
        model: image.model_id
      )

      # Notify user
      UserMailer.image_ready(user, prompt).deliver_later
    rescue RubyLLM::Error => e
      ErrorLogger.log(e, context: { prompt: prompt, user_id: user_id })
      UserMailer.image_failed(user, prompt, e.message).deliver_later
    end
  end
end
```

## Example Use Cases

### Product Visualization

```ruby
def visualize_product(product_name, description)
  prompt = "#{product_name}: #{description}. " \
           "Professional product photography on white background, " \
           "detailed, commercial quality."

  RubyLLM.paint(prompt, size: "1024x1024")
end

image = visualize_product(
  "Ergonomic Office Chair",
  "Modern mesh back office chair with adjustable armrests and lumbar support"
)
```

### Art Generation for Content

```ruby
def generate_article_header(title, style)
  prompt = "Header image for an article titled '#{title}'. " \
           "Style: #{style}. Wide format, suitable for a blog header."

  RubyLLM.paint(prompt, size: "1792x1024")
end

image = generate_article_header(
  "The Future of Renewable Energy",
  "Minimalist digital illustration with clean lines and a blue-green color palette"
)
```

## Next Steps

Now that you understand image generation, you might want to explore:

- [Embeddings]({% link guides/embeddings.md %}) for vector representations
- [Chat with Images]({% link guides/chat.md %}#working-with-images) to analyze images with AI
- [Error Handling]({% link guides/error-handling.md %}) for robust applications
