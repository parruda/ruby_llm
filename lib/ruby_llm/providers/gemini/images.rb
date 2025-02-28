# frozen_string_literal: true

module RubyLLM
  module Providers
    module Gemini
      # Image generation methods for the Gemini API implementation
      module Images
        def images_url(model:)
          "models/#{model}:predict"
        end

        def paint(prompt, model:, size:) # rubocop:disable Lint/UnusedMethodArgument
          payload = render_image_payload(prompt)

          response = post(images_url(model:), payload)
          parse_image_response(response)
        end

        def render_image_payload(prompt)
          {
            instances: [
              {
                prompt: prompt
              }
            ],
            parameters: {
              sampleCount: 1
            }
          }
        end

        def parse_image_response(response) # rubocop:disable Metrics/MethodLength
          data = response.body
          image_data = data['predictions']&.first

          unless image_data&.key?('bytesBase64Encoded')
            raise Error, 'Unexpected response format from Gemini image generation API'
          end

          # Extract mime type and base64 data
          mime_type = image_data['mimeType'] || 'image/png'
          base64_data = image_data['bytesBase64Encoded']

          Image.new(
            data: base64_data,
            mime_type: mime_type
          )
        end
      end
    end
  end
end
