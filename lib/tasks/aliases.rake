# frozen_string_literal: true

require 'json'

namespace :aliases do # rubocop:disable Metrics/BlockLength
  desc 'Generate aliases.json from models in the registry'
  task :generate do # rubocop:disable Metrics/BlockLength
    require 'ruby_llm'

    # Group models by provider
    models = Hash.new { |h, k| h[k] = [] }

    RubyLLM.models.all.each do |model|
      models[model.provider] << model.id
    end

    aliases = {}

    # OpenAI models
    models['openai'].each do |model|
      openrouter_model = "openai/#{model}"
      next unless models['openrouter'].include?(openrouter_model)

      alias_key = model.gsub('-latest', '')
      aliases[alias_key] = {
        'openai' => model,
        'openrouter' => openrouter_model
      }
    end

    anthropic_latest = group_anthropic_models_by_base_name(models['anthropic'])

    anthropic_latest.each do |base_name, latest_model|
      openrouter_variants = [
        "anthropic/#{base_name}", # anthropic/claude-3-5-sonnet
        "anthropic/#{base_name.gsub(/-(\d)/, '.\1')}", # anthropic/claude-3.5-sonnet
        "anthropic/#{base_name.gsub(/claude-(\d+)-(\d+)/, 'claude-\1.\2')}", # claude-3-5 -> claude-3.5
        "anthropic/#{base_name.gsub(/(\d+)-(\d+)/, '\1.\2')}" # any X-Y -> X.Y pattern
      ]

      openrouter_model = openrouter_variants.find { |v| models['openrouter'].include?(v) }

      bedrock_model = find_best_bedrock_model(latest_model, models['bedrock'])

      next unless openrouter_model || bedrock_model || models['anthropic'].include?(latest_model)

      aliases[base_name] = {
        'anthropic' => latest_model
      }

      aliases[base_name]['openrouter'] = openrouter_model if openrouter_model
      aliases[base_name]['bedrock'] = bedrock_model if bedrock_model
    end

    models['bedrock'].each do |bedrock_model|
      next unless bedrock_model.start_with?('anthropic.')

      next unless bedrock_model =~ /anthropic\.(claude-[\d\.]+-[a-z]+)/

      base_name = Regexp.last_match(1)
      anthropic_name = base_name.tr('.', '-')

      next if aliases[anthropic_name]

      openrouter_variants = [
        "anthropic/#{anthropic_name}",
        "anthropic/#{base_name}" # Keep the dots
      ]

      openrouter_model = openrouter_variants.find { |v| models['openrouter'].include?(v) }

      aliases[anthropic_name] = {
        'bedrock' => bedrock_model
      }

      aliases[anthropic_name]['anthropic'] = anthropic_name if models['anthropic'].include?(anthropic_name)
      aliases[anthropic_name]['openrouter'] = openrouter_model if openrouter_model
    end

    models['gemini'].each do |model|
      openrouter_variants = [
        "google/#{model}",
        "google/#{model.gsub('gemini-', 'gemini-').tr('.', '-')}",
        "google/#{model.gsub('gemini-', 'gemini-')}"
      ]

      openrouter_model = openrouter_variants.find { |v| models['openrouter'].include?(v) }
      next unless openrouter_model

      alias_key = model.gsub('-latest', '')
      aliases[alias_key] = {
        'gemini' => model,
        'openrouter' => openrouter_model
      }
    end

    models['deepseek'].each do |model|
      openrouter_model = "deepseek/#{model}"
      next unless models['openrouter'].include?(openrouter_model)

      alias_key = model.gsub('-latest', '')
      aliases[alias_key] = {
        'deepseek' => model,
        'openrouter' => openrouter_model
      }
    end

    sorted_aliases = aliases.sort.to_h
    File.write(RubyLLM::Aliases.aliases_file, JSON.pretty_generate(sorted_aliases))

    puts "Generated #{sorted_aliases.size} aliases"
  end

  def group_anthropic_models_by_base_name(anthropic_models) # rubocop:disable Rake/MethodDefinitionInTask
    grouped = Hash.new { |h, k| h[k] = [] }

    anthropic_models.each do |model|
      base_name = extract_base_name(model)
      grouped[base_name] << model
    end

    latest_models = {}
    grouped.each do |base_name, model_list|
      if model_list.size == 1
        latest_models[base_name] = model_list.first
      else
        latest_model = model_list.max_by { |model| extract_date_from_model(model) }
        latest_models[base_name] = latest_model
      end
    end

    latest_models
  end

  def extract_base_name(model) # rubocop:disable Rake/MethodDefinitionInTask
    if model =~ /^(.+)-(\d{8})$/
      Regexp.last_match(1)
    else
      model
    end
  end

  def extract_date_from_model(model) # rubocop:disable Rake/MethodDefinitionInTask
    if model =~ /-(\d{8})$/
      Regexp.last_match(1)
    else
      '00000000'
    end
  end

  def find_best_bedrock_model(anthropic_model, bedrock_models) # rubocop:disable Metrics/PerceivedComplexity,Rake/MethodDefinitionInTask
    base_pattern = case anthropic_model
                   when 'claude-2.0', 'claude-2'
                     'claude-v2'
                   when 'claude-2.1'
                     'claude-v2:1'
                   when 'claude-instant-v1', 'claude-instant'
                     'claude-instant'
                   else
                     extract_base_name(anthropic_model)
                   end

    matching_models = bedrock_models.select do |bedrock_model|
      model_without_prefix = bedrock_model.sub(/^(?:us\.)?anthropic\./, '')
      model_without_prefix.start_with?(base_pattern)
    end

    return nil if matching_models.empty?

    begin
      model_info = RubyLLM.models.find(anthropic_model)
      target_context = model_info.context_window
    rescue StandardError
      target_context = nil
    end

    if target_context
      target_k = target_context / 1000

      with_context = matching_models.select do |m|
        m.include?(":#{target_k}k") || m.include?(":0:#{target_k}k")
      end

      return with_context.first if with_context.any?
    end

    matching_models.min_by do |model|
      context_priority = if model =~ /:(?:\d+:)?(\d+)k/
                           -Regexp.last_match(1).to_i
                         else
                           0
                         end

      version_priority = if model =~ /-v(\d+):/
                           -Regexp.last_match(1).to_i
                         else
                           0
                         end

      # Prefer models with explicit context windows
      has_context_priority = model.include?('k') ? -1 : 0
      [has_context_priority, context_priority, version_priority]
    end
  end
end
