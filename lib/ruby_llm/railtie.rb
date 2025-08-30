# frozen_string_literal: true

module RubyLLM
  # Rails integration for RubyLLM
  class Railtie < Rails::Railtie
    ActiveSupport::Inflector.inflections(:en) do |inflect|
      inflect.acronym 'RubyLLM'
    end

    ActiveSupport.on_load :active_record do
      if RubyLLM.config.model_registry_class
        require 'ruby_llm/active_record/acts_as'
        ::ActiveRecord::Base.include RubyLLM::ActiveRecord::ActsAs
      else
        require 'ruby_llm/active_record/acts_as_legacy'
        ::ActiveRecord::Base.include RubyLLM::ActiveRecord::ActsAsLegacy

        Rails.logger.warn(
          'RubyLLM: String-based model fields are deprecated and will be removed in RubyLLM 2.0.0. ' \
          'Please migrate to the DB-backed model registry. ' \
          "Run 'rails generate ruby_llm:migrate_model_fields' to upgrade."
        )
      end
    end

    generators do
      require 'generators/ruby_llm/install_generator'
      require 'generators/ruby_llm/migrate_model_fields_generator'
    end

    rake_tasks do
      load 'tasks/ruby_llm.rake'
    end
  end
end
