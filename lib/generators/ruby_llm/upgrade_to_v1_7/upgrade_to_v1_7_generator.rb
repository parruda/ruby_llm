# frozen_string_literal: true

require 'rails/generators'
require 'rails/generators/active_record'

module RubyLLM
  class UpgradeToV17Generator < Rails::Generators::Base # rubocop:disable Style/Documentation
    include Rails::Generators::Migration

    namespace 'ruby_llm:upgrade_to_v1_7'
    source_root File.expand_path('templates', __dir__)

    # Override source_paths to include install templates
    def self.source_paths
      [
        File.expand_path('templates', __dir__),
        File.expand_path('../install/templates', __dir__)
      ]
    end

    argument :model_mappings, type: :array, default: [], banner: 'chat:ChatName message:MessageName ...'

    desc 'Upgrades existing RubyLLM apps to v1.7 with new Rails-like API\n' \
         'Usage: rails g ruby_llm:upgrade_to_v1_7 [chat:ChatName] [message:MessageName] ...'

    def self.next_migration_number(dirname)
      ::ActiveRecord::Generators::Base.next_migration_number(dirname)
    end

    def parse_model_mappings
      @model_names = {
        chat: 'Chat',
        message: 'Message',
        tool_call: 'ToolCall',
        model: 'Model'
      }

      model_mappings.each do |mapping|
        if mapping.include?(':')
          key, value = mapping.split(':', 2)
          @model_names[key.to_sym] = value.classify
        end
      end

      @model_names
    end

    %i[chat message tool_call model].each do |type|
      define_method("#{type}_model_name") do
        @model_names ||= parse_model_mappings
        @model_names[type]
      end

      define_method("#{type}_table_name") do
        table_name_for(send("#{type}_model_name"))
      end
    end

    def create_migration_file
      @model_table_already_existed = table_exists?(table_name_for(model_model_name))

      # First check if models table exists, if not create it
      unless @model_table_already_existed
        migration_template 'create_models_migration.rb.tt',
                           "db/migrate/create_#{table_name_for(model_model_name)}.rb",
                           migration_version: migration_version,
                           model_model_name: model_model_name

        sleep 1 # Ensure different timestamp
      end

      migration_template 'migration.rb.tt',
                         'db/migrate/migrate_to_ruby_llm_model_references.rb',
                         migration_version: migration_version,
                         chat_model_name: chat_model_name,
                         message_model_name: message_model_name,
                         tool_call_model_name: tool_call_model_name,
                         model_model_name: model_model_name,
                         model_table_already_existed: @model_table_already_existed
    end

    def create_model_file
      # Check if Model file already exists
      model_path = "app/models/#{model_model_name.underscore}.rb"

      if File.exist?(Rails.root.join(model_path))
        say_status :skip, model_path, :yellow
      else
        create_file model_path do
          <<~RUBY
            class #{model_model_name} < ApplicationRecord
              #{acts_as_model_declaration}
            end
          RUBY
        end
      end
    end

    def acts_as_model_declaration
      params = []

      add_association_params(params, :chats, chat_table_name, chat_model_name, plural: true)

      "acts_as_model#{" #{params.join(', ')}" if params.any?}"
    end

    def update_initializer
      initializer_path = 'config/initializers/ruby_llm.rb'

      unless File.exist?(initializer_path)
        say_status :warning, 'No initializer found. Creating one...', :yellow
        template '../install/templates/initializer.rb.tt', initializer_path
        return
      end

      initializer_content = File.read(initializer_path)

      return if initializer_content.include?('config.use_new_acts_as')

      inject_into_file initializer_path, before: /^end/ do
        lines = ["\n  # Enable the new Rails-like API", '  config.use_new_acts_as = true']
        lines << "  config.model_registry_class = \"#{model_model_name}\"" if model_model_name != 'Model'
        lines << "\n"
        lines.join("\n")
      end
    end

    def show_next_steps
      say_status :success, 'Upgrade prepared!', :green
      say <<~INSTRUCTIONS

        Next steps:
        1. Review the generated migrations
        2. Run: rails db:migrate
        3. Update your code to use the new API

        ⚠️  If you get "undefined method 'acts_as_model'" during migration:
           Add this to config/application.rb BEFORE your Application class:

           RubyLLM.configure do |config|
             config.use_new_acts_as = true
           end

        📚 See the full migration guide: https://rubyllm.com/upgrading-to-1-7/

      INSTRUCTIONS
    end

    private

    def migration_version
      "[#{Rails::VERSION::MAJOR}.#{Rails::VERSION::MINOR}]"
    end

    def add_association_params(params, default_assoc, table_name, model_name, plural: false)
      assoc = plural ? table_name.to_sym : table_name.singularize.to_sym

      return if assoc == default_assoc

      params << "#{default_assoc}: :#{assoc}"
      params << "#{default_assoc}_class: '#{model_name}'" if model_name != assoc.to_s.classify
    end

    def table_name_for(model_name)
      # Convert namespaced model names to proper table names
      # e.g., "Assistant::Chat" -> "assistant_chats" (not "assistant/chats")
      model_name.underscore.pluralize.tr('/', '_')
    end

    def table_exists?(table_name)
      ::ActiveRecord::Base.connection.table_exists?(table_name)
    rescue StandardError
      false
    end

    def postgresql?
      ::ActiveRecord::Base.connection.adapter_name.downcase.include?('postgresql')
    rescue StandardError
      false
    end
  end
end
