# frozen_string_literal: true

ENV['RAILS_ENV'] = 'test'

# Load the Rails application but don't initialize yet
require_relative 'spec_helper'
require_relative 'dummy/config/application'

# This is a workaround for the railtie not working properly with appraisal
ActiveSupport.on_load(:active_record) do
  require 'ruby_llm/active_record/acts_as'
  include RubyLLM::ActiveRecord::ActsAs
end

Rails.application.initialize! unless Rails.application.initialized?

begin
  ActiveRecord::Tasks::DatabaseTasks.create_current
rescue ActiveRecord::DatabaseAlreadyExists
  # Database already exists, that's fine
end

ActiveRecord::Tasks::DatabaseTasks.load_schema_current

RubyLLM.models.load_from_json!
Model.save_to_database
