# frozen_string_literal: true

ENV['RAILS_ENV'] = 'test'

require_relative 'dummy/config/environment'
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

# Ensure RubyLLM ActiveRecord integration is included
ActiveRecord::Base.include RubyLLM::ActiveRecord::ActsAs

# Load models from JSON and save to database
RubyLLM.models.load_from_json!
Model.save_to_database
