# frozen_string_literal: true

module RubyLLM
  module Providers
    module Gemini
      # Media handling methods for the Gemini API integration
      module Media # rubocop:disable Metrics/ModuleLength
        module_function

        def format_image(part) # rubocop:disable Metrics/AbcSize,Metrics/MethodLength,Metrics/PerceivedComplexity
          source = part[:source]

          if source.is_a?(String)
            if source.start_with?('http')
              # Handle URL
              {
                inline_data: {
                  mime_type: mime_type_for_image(source),
                  data: fetch_and_encode_image(source)
                }
              }
            else
              # Handle file path
              {
                inline_data: {
                  mime_type: mime_type_for_image(source),
                  data: encode_image_file(source)
                }
              }
            end
          elsif source.is_a?(Hash)
            if source[:url]
              # Handle URL in hash
              {
                inline_data: {
                  mime_type: source[:media_type] || mime_type_for_image(source[:url]),
                  data: fetch_and_encode_image(source[:url])
                }
              }
            else
              # Handle data in hash
              {
                inline_data: {
                  mime_type: source[:media_type] || 'image/jpeg',
                  data: source[:data]
                }
              }
            end
          end
        end

        def format_pdf(part) # rubocop:disable Metrics/MethodLength
          source = part[:source]

          if source.is_a?(String) && source.start_with?('http')
            # Handle URL
            {
              inline_data: {
                mime_type: 'application/pdf',
                data: fetch_and_encode_pdf(source)
              }
            }
          else
            # Handle file path or data
            {
              inline_data: {
                mime_type: 'application/pdf',
                data: part[:content] ? Base64.strict_encode64(part[:content]) : encode_pdf_file(source)
              }
            }
          end
        end

        def format_audio(part) # rubocop:disable Metrics/MethodLength
          source = part[:source]

          if source.is_a?(String) && source.start_with?('http')
            # Handle URL
            {
              file_data: {
                mime_type: mime_type_for_audio(source),
                file_uri: source
              }
            }
          else
            # Handle file path or data
            content = part[:content] || File.read(source)
            {
              inline_data: {
                mime_type: mime_type_for_audio(source),
                data: Base64.strict_encode64(content)
              }
            }
          end
        end

        def mime_type_for_image(path)
          ext = File.extname(path).downcase.delete('.')
          case ext
          when 'png' then 'image/png'
          when 'gif' then 'image/gif'
          when 'webp' then 'image/webp'
          else 'image/jpeg'
          end
        end

        def mime_type_for_audio(path)
          ext = File.extname(path).downcase.delete('.')
          case ext
          when 'mp3' then 'audio/mpeg'
          when 'ogg' then 'audio/ogg'
          else 'audio/wav'
          end
        end

        def fetch_and_encode_image(url)
          response = Faraday.get(url)
          Base64.strict_encode64(response.body)
        end

        def fetch_and_encode_pdf(url)
          response = Faraday.get(url)
          Base64.strict_encode64(response.body)
        end

        def encode_image_file(path)
          Base64.strict_encode64(File.read(path))
        end

        def encode_pdf_file(path)
          Base64.strict_encode64(File.read(path))
        end
      end
    end
  end
end
