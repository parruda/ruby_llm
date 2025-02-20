# frozen_string_literal: true

require_relative 'lib/ruby_llm/version'

Gem::Specification.new do |spec|
  spec.name          = 'ruby_llm'
  spec.version       = RubyLLM::VERSION
  spec.authors       = ['Carmine Paolino']
  spec.email         = ['carmine@paolino.me']

  spec.summary       = 'Beautiful Ruby interface to modern AI'
  spec.description   = 'A delightful Ruby way to work with AI. Chat in text, analyze and generate images, understand' \
                       ' audio, and use tools through a unified interface to OpenAI, Anthropic, Google, and DeepSeek.' \
                       ' Built for developer happiness with automatic token counting, proper streaming, and Rails' \
                       ' integration. No wrapping your head around multiple APIs - just clean Ruby code that works.'
  spec.homepage      = 'https://github.com/crmne/ruby_llm'
  spec.license       = 'MIT'
  spec.required_ruby_version = Gem::Requirement.new('>= 3.1.0')

  spec.metadata['homepage_uri'] = spec.homepage
  spec.metadata['source_code_uri'] = spec.homepage
  spec.metadata['changelog_uri'] = "#{spec.homepage}/commits/main"
  spec.metadata['documentation_uri'] = spec.homepage
  spec.metadata['bug_tracker_uri'] = "#{spec.homepage}/issues"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(test|spec|features)/}) }
  end
  spec.bindir        = 'exe'
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ['lib']

  # Runtime dependencies
  spec.add_dependency 'event_stream_parser', '>= 0.3.0', '< 2.0.0'
  spec.add_dependency 'faraday', '>= 2.0'
  spec.add_dependency 'faraday-multipart', '>= 1.0'
  spec.add_dependency 'faraday-retry', '>= 2.0'
  spec.add_dependency 'zeitwerk', '>= 2.6'

  # Rails integration dependencies
  spec.add_development_dependency 'activerecord', '>= 6.0', '< 9.0'
  spec.add_development_dependency 'activesupport', '>= 6.0', '< 9.0'

  # Development dependencies
  spec.add_development_dependency 'bundler', '>= 2.0'
  spec.add_development_dependency 'dotenv'
  spec.add_development_dependency 'irb'
  spec.add_development_dependency 'nokogiri'
  spec.add_development_dependency 'overcommit', '>= 0.66'
  spec.add_development_dependency 'pry', '>= 0.14'
  spec.add_development_dependency 'rake', '>= 13.0'
  spec.add_development_dependency 'rdoc'
  spec.add_development_dependency 'reline'
  spec.add_development_dependency 'rspec', '~> 3.12'
  spec.add_development_dependency 'rubocop', '>= 1.0'
  spec.add_development_dependency 'rubocop-rake', '>= 0.6'
  spec.add_development_dependency 'simplecov', '>= 0.21'
  spec.add_development_dependency 'sqlite3'
  spec.add_development_dependency 'webmock', '~> 3.18'
  spec.add_development_dependency 'yard', '>= 0.9'
end
