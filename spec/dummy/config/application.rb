# frozen_string_literal: true

require File.expand_path("boot", __dir__)

require "logger"
require "rails/all"
Bundler.require(*Rails.groups)

require "switchman_inst_jobs"

module Dummy
  class Application < Rails::Application
    config.root = File.expand_path("..", __dir__)
    config.active_record.dump_schema_after_migration = false

    # Add our switchman-inst-jobs gem migrations. It's important that these are
    # absolute paths since Switchman won't run them relative to the dummy root.
    ActiveRecord::Migrator.migrations_paths = [
      config.root.join("db/migrate"),
      config.root.join("../../db/migrate")
    ]
  end
end
