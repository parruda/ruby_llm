# frozen_string_literal: true

ENV['RAILS_ENV'] = 'test'

# Load Rails application but don't initialize yet
require_relative 'dummy/config/application'

# Ensure RubyLLM ActiveRecord integration is set up before models load
ActiveSupport.on_load(:active_record) do
  require 'ruby_llm/active_record/acts_as'
  include RubyLLM::ActiveRecord::ActsAs
end

# Now initialize Rails (this will load models)
Rails.application.initialize! unless Rails.application.initialized?

require_relative 'spec_helper'

# Ensure database is properly set up
begin
  # Create database if it doesn't exist
  ActiveRecord::Tasks::DatabaseTasks.create_current
rescue ActiveRecord::DatabaseAlreadyExists
  # Database already exists, that's fine
end

# Ensure schema is loaded for this spec file
ActiveRecord::Tasks::DatabaseTasks.load_schema_current

# Load models from JSON and save to database
RubyLLM.models.load_from_json!
Model.save_to_database
