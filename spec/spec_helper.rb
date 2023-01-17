ENV['RAILS_ENV'] ||= 'test'

if /^2\.6/ =~ RUBY_VERSION && /6\.1/ =~ ENV.fetch('BUNDLE_GEMFILE', nil) # Limit coverage to one build
  require 'simplecov'

  SimpleCov.start do
    enable_coverage :branch
    minimum_coverage 90

    add_filter 'db/migrate'
    add_filter 'lib/switchman_inst_jobs/version.rb'
    add_filter 'lib/switchman_inst_jobs/new_relic.rb'
    add_filter 'spec'

    track_files 'lib/**/*.rb'
  end
end

require 'pry'

require File.expand_path('dummy/config/environment', __dir__)
require 'rspec/rails'
require 'switchman/r_spec_helper'

# No reason to add default sleep time to specs:
Delayed::Settings.sleep_delay         = 0
Delayed::Settings.sleep_delay_stagger = 0

RSpec.configure do |config|
  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
    expectations.syntax = :expect
  end

  config.mock_with :rspec do |mocks|
    mocks.allow_message_expectations_on_nil = false
  end

  config.default_formatter = 'doc' if config.files_to_run.one?

  config.filter_rails_from_backtrace!

  config.order = :random
  Kernel.srand config.seed

  config.use_transactional_fixtures = true

  config.around(:each) do |example|
    if Switchman::Shard.instance_variable_defined?(:@jobs_scope_empty)
      Switchman::Shard.remove_instance_variable(:@jobs_scope_empty)
    end
    example.run
  end

  config.around(:each, use_transactional_fixtures: false) do |example|
    self.use_transactional_tests = false
    example.run
    self.use_transactional_tests = true
  end
end
