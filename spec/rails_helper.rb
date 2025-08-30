# frozen_string_literal: true

ENV['RAILS_ENV'] = 'test'

# Load the Rails application but don't initialize yet
require_relative 'spec_helper'
require_relative 'dummy/config/environment'
require 'ruby_llm/railtie'
require 'ruby_llm/active_record/acts_as'

begin
  ActiveRecord::Tasks::DatabaseTasks.create_current
rescue ActiveRecord::DatabaseAlreadyExists
  # Database already exists, that's fine
end

ActiveRecord::Tasks::DatabaseTasks.load_schema_current

RubyLLM.models.load_from_json!
Model.save_to_database
