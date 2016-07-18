require File.expand_path('../boot', __FILE__)

require 'rails/all'
Bundler.require(*Rails.groups)

require 'switchman_inst_jobs'

module Dummy
  class Application < Rails::Application
    config.root = File.expand_path('../..', __FILE__)

    # Do not swallow errors in after_commit/after_rollback callbacks.
    if Rails.version < '5'
      config.active_record.raise_in_transactional_callbacks = true
    end

    config.active_record.dump_schema_after_migration = false

    # Kill the ActiveRecord::Migration inheritance deprecation warning.
    if Rails.version >= '5'
      module Migration
        def migrate(*args)
          ActiveRecord::Migration.instance_method(:migrate).bind(self).call(*args)
        end
      end
      ActiveRecord::Migration::Compatibility::Legacy.prepend Migration
    end

    # Add our switchman-inst-jobs gem migrations. It's important that these are
    # absolute paths since Switchman won't run them relative to the dummy root.
    ActiveRecord::Migrator.migrations_paths = [
      config.root.join('db/migrate'),
      config.root.join('../../db/migrate')
    ]
    # Also configure the paths for db:migrate task.
    config.paths['db/migrate'] = [
      config.root.join('db/migrate'),
      config.root.join('../../db/migrate')
    ]
  end
end
