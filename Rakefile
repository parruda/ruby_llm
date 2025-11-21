# frozen_string_literal: true

require 'bundler/setup'
Bundler::GemHelper.install_tasks(name: 'ruby_llm_swarm')
require 'rake/clean'

Dir.glob('lib/tasks/**/*.rake').each { |r| load r }

desc 'Run overcommit hooks and update models'
task :default do
  sh 'overcommit --run'
  Rake::Task['models'].invoke
end
