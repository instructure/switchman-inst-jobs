if /^2\.4/ =~ RUBY_VERSION && /5\.0/ =~ ENV['BUNDLE_GEMFILE'] # Limit coverage to one build
  require 'simplecov'

  SimpleCov.start do
    add_filter 'db/migrate'
    add_filter 'lib/switchman_inst_jobs/version.rb'
    add_filter 'spec'
    track_files 'lib/**/*.rb'
  end

  SimpleCov.minimum_coverage(90)
end

require 'pry'

require File.expand_path('../dummy/config/environment', __FILE__)
require 'rspec/rails'

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
    Switchman::Shard.clear_cache
    unless Switchman::Shard.default(reload: true).is_a?(Switchman::Shard)
      Switchman::Shard.reset_column_information
      Switchman::Shard.create!(default: true)
      Switchman::Shard.default(reload: true)
    end
    example.run
  end
end
