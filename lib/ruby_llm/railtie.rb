# frozen_string_literal: true

module RubyLLM
  # Rails integration for RubyLLM
  class Railtie < Rails::Railtie
    initializer 'ruby_llm.active_record' do
      ActiveSupport.on_load :active_record do
        include RubyLLM::ActiveRecord::ActsAs
      end
    end

    rake_tasks do
      # Load original tasks
      path = File.expand_path(__dir__)
      Dir.glob("#{path}/../tasks/**/*.rake").each { |f| load f }

      # Create namespaced aliases for Rails apps
      namespace :ruby_llm do
        task 'aliases:generate' => 'aliases:generate'
        task 'models:update' => 'models:update'
        task 'models:docs' => 'models:docs'
        task 'release:verify_cassettes' => 'release:verify_cassettes'
        task 'vcr:record' => 'vcr:record'
      end

      # Remove original tasks to avoid namespace pollution in Rails apps
      %w[aliases:generate models:update models:docs release:verify_cassettes vcr:record].each do |task_name|
        Rake::Task[task_name].clear if Rake::Task.task_defined?(task_name)
      end
    end
  end
end
