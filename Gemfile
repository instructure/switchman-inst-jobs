# frozen_string_literal: true

source "https://rubygems.org"

plugin "bundler-multilock", "1.4.0"
return unless Plugin.installed?("bundler-multilock")

Plugin.send(:load_plugin, "bundler-multilock")

gemspec

gem "diplomat", "~> 2.5", require: false
gem "newrelic_rpm", require: false
gem "pg", "~> 1.0", require: false
gem "rake", "~> 13", require: false
gem "rspec", "~> 3.10", require: false
gem "rspec-rails", "~> 7.0", require: false
gem "rubocop-inst", "~> 1", require: false
gem "rubocop-rails", "~> 2.10", require: false
gem "rubocop-rake", "~> 0.6", require: false
gem "rubocop-rspec", "~> 3.0", require: false
gem "rubocop-rspec_rails", "~> 2.32"
gem "simplecov", "~> 0.21", require: false

lockfile "activerecord-7.2" do
  gem "activerecord", "~> 7.2.0"
  gem "railties", "~> 7.2.0"
end

lockfile "activerecord-8.0" do
  gem "activerecord", "~> 8.0.0"
  gem "railties", "~> 8.0.0"
end

lockfile do
  gem "activerecord", "~> 8.1.0"
  gem "railties", "~> 8.1.0"
end
