# frozen_string_literal: true

source "https://rubygems.org"

plugin "bundler-multilock", "1.1.2"
return unless Plugin.installed?("bundler-multilock")

Plugin.send(:load_plugin, "bundler-multilock")

gemspec

lockfile "activerecord-6.1" do
  gem "activerecord", "~> 6.1.0"
  gem "activerecord-pg-extensions", "~> 0.4"
  gem "activesupport", "~> 6.1.0"
  gem "railties", "~> 6.1.0"
end

lockfile "activerecord-7.0" do
  gem "activerecord", "~> 7.0.0"
  gem "activerecord-pg-extensions", "~> 0.5"
  gem "activesupport", "~> 7.0.0"
  gem "railties", "~> 7.0.0"
end

lockfile "activerecord-7.1" do
  gem "activerecord", "~> 7.1.0"
  gem "activerecord-pg-extensions", "~> 0.5"
  gem "activesupport", "~> 7.1.0"
  gem "railties", "~> 7.1.0"
end
