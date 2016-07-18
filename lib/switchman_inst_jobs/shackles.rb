module SwitchmanInstJobs
  module Shackles
    module ClassMethods
      def activate(env, &block)
        if ::ActiveRecord::Migration.open_migrations.positive?
          yield
        else
          super
        end
      end
    end
  end
end
