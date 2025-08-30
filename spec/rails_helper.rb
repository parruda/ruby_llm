# frozen_string_literal: true

ENV['RAILS_ENV'] = 'test'

require_relative 'dummy/config/environment'

ActiveRecord::Base.include RubyLLM::ActiveRecord::ActsAs

require_relative 'spec_helper'

begin
  ActiveRecord::Tasks::DatabaseTasks.create_current
rescue ActiveRecord::DatabaseAlreadyExists
  # Database already exists, that's fine
end

ActiveRecord::Tasks::DatabaseTasks.load_schema_current

RubyLLM.models.load_from_json!
Model.save_to_database
