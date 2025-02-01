# frozen_string_literal: true

namespace :ruby_llm do
  desc 'Update available models from providers'
  task :update_models do
    require 'ruby_llm'

    # Configure API keys
    RubyLLM.configure do |config|
      config.openai_api_key = ENV.fetch('OPENAI_API_KEY')
      config.anthropic_api_key = ENV.fetch('ANTHROPIC_API_KEY')
    end

    # Get all models
    models = RubyLLM.models.refresh

    # Write to models.json
    models_file = File.expand_path('../../lib/ruby_llm/models.json', __dir__)
    File.write(models_file, JSON.pretty_generate(models.map(&:to_h)))

    puts "Updated models.json with #{models.size} models:"
    puts "OpenAI models: #{models.count { |m| m.provider == 'openai' }}"
    puts "Anthropic models: #{models.count { |m| m.provider == 'anthropic' }}"
  end
end
