# frozen_string_literal: true

source "https://rubygems.org"

plugin "bundler-multilock", "1.3.4"
return unless Plugin.installed?("bundler-multilock")

Plugin.send(:load_plugin, "bundler-multilock")

gemspec

lockfile "activerecord-7.0" do
  gem "activerecord", "~> 7.0.0"
  gem "bigdecimal", "~> 3.1", require: RUBY_VERSION >= "3.4.0"
  gem "drb", "~> 2.1", require: RUBY_VERSION >= "3.4.0"
  gem "mutex_m", "~> 0.1", require: RUBY_VERSION >= "3.4.0"
  gem "railties", "~> 7.0.0"
end

lockfile do
  gem "activerecord", "~> 7.1.0"
  gem "activerecord-pg-extensions", "~> 0.5"
  gem "railties", "~> 7.1.0"
end
