# frozen_string_literal: true

source "https://rubygems.org"

plugin "bundler-multilock", "1.3.4"
return unless Plugin.installed?("bundler-multilock")

Plugin.send(:load_plugin, "bundler-multilock")

gemspec

gem "bundler", require: false
gem "byebug", require: false
gem "diplomat", "~> 2.6.0", require: false
gem "newrelic_rpm", require: false
gem "pg", "~> 1.0", require: false
gem "pry", "~> 0", require: false
gem "rake", "~> 13", require: false
gem "rspec", "~> 3.10", require: false
gem "rspec-rails", "~> 8.0", ">= 8.0.0", require: false
gem "rubocop-inst", "~> 1", require: false
gem "rubocop-rails", "~> 2.31", ">= 2.31.0", require: false
gem "rubocop-rake", "~> 0.6", require: false
gem "rubocop-rspec", "~> 3.0", require: false
gem "simplecov", "~> 0.21", require: false
gem "zeitwerk", "~> 2.6", "< 2.7", require: false

lockfile "activerecord-7.1" do
  gem "activerecord", "~> 8.0.3"
  gem "railties", "~> 8.0.3"
end

lockfile "activerecord-7.2" do
  gem "activerecord", "~> 8.0.3"
  gem "railties", "~> 8.0.3"
end

lockfile do
  gem "activerecord", "~> 8.0.3"
  gem "railties", "~> 8.0.3"
end
