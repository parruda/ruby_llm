# frozen_string_literal: true

namespace :ruby_llm do
  desc 'Update available models from providers'
  task :update_models do
    require 'ruby_llm'

    # Configure API keys
    RubyLLM.configure do |config|
      config.openai_api_key = ENV.fetch('OPENAI_API_KEY')
      config.anthropic_api_key = ENV.fetch('ANTHROPIC_API_KEY')
      config.gemini_api_key = ENV['GEMINI_API_KEY']
      config.deepseek_api_key = ENV['DEEPSEEK_API_KEY']
    end

    # Get all models
    models = RubyLLM.models.refresh!

    # Write to models.json
    models_file = File.expand_path('../../lib/ruby_llm/models.json', __dir__)
    File.write(models_file, JSON.pretty_generate(models.map(&:to_h)))

    puts "Updated models.json with #{models.size} models:"
    RubyLLM::Provider.providers.each do |provider_sym, provider_module|
      provider_name = provider_module.to_s.split('::').last
      puts "#{provider_name} models: #{models.count { |m| m.provider == provider_sym.to_s }}"
    end
  end
end
