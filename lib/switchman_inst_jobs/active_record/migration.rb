module SwitchmanInstJobs
  module ActiveRecord
    module Migration
      module ClassMethods
        def self.included(klass)
          klass.send(:attr_writer, :open_migrations)
        end

        def open_migrations
          @open_migrations ||= 0
        end
      end

      def migrate(direction)
        ::ActiveRecord::Migration.open_migrations += 1
        super
      ensure
        ::ActiveRecord::Migration.open_migrations -= 1
      end

      def copy(destination, sources, options = {})
        if sources.delete('delayed_engine')
          # rubocop:disable Rails/Output
          puts 'NOTE: Not installing delayed_engine migrations in an application using switchman-inst-jobs'
          puts '(use rake switchman_inst_jobs:install:migrations instead)'
          # rubocop:enable Rails/Output
        end
        super
      end
    end
  end
end

ActiveRecord::Migration.prepend SwitchmanInstJobs::ActiveRecord::Migration
ActiveRecord::Migration.singleton_class.include(
  SwitchmanInstJobs::ActiveRecord::Migration::ClassMethods
)
