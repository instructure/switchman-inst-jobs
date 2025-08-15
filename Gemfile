# frozen_string_literal: true

source "https://rubygems.org"

plugin "bundler-multilock", "1.3.4"
return unless Plugin.installed?("bundler-multilock")

Plugin.send(:load_plugin, "bundler-multilock")

gemspec

gem "bundler", require: false
gem "byebug", require: false
gem "diplomat", "~> 2.5.1", require: false
gem "newrelic_rpm", require: false
gem "pg", "~> 1.0", require: false
gem "pry", "~> 0", require: false
gem "rake", "~> 13", require: false
gem "rspec", "~> 3.10", require: false
gem "rspec-rails", "~> 7.0", require: false
gem "rubocop-inst", "~> 1", require: false
gem "rubocop-rails", "~> 2.10", require: false
gem "rubocop-rake", "~> 0.6", require: false
gem "rubocop-rspec", "~> 3.0", require: false
gem "simplecov", "~> 0.21", require: false
gem "zeitwerk", "~> 2.6", "< 2.7", require: false

lockfile "activerecord-7.0" do
  gem "activerecord", "~> 7.2.2", ">= 7.2.2.2"
  gem "base64", "~> 0.1", require: RUBY_VERSION >= "3.4.0"
  gem "bigdecimal", "~> 3.1", require: RUBY_VERSION >= "3.4.0"
  gem "drb", "~> 2.1", require: RUBY_VERSION >= "3.4.0"
  gem "mutex_m", "~> 0.1", require: RUBY_VERSION >= "3.4.0"
  gem "railties", "~> 7.0.0"
end

lockfile "activerecord-7.1" do
  gem "activerecord", "~> 7.2.2", ">= 7.2.2.2"
  gem "activerecord-pg-extensions", "~> 0.5"
  gem "railties", "~> 7.1.0"
end

lockfile do
  gem "activerecord", "~> 7.2.2", ">= 7.2.2.2"
  gem "activerecord-pg-extensions", "~> 0.5"
  gem "railties", "~> 7.2.0"
end
