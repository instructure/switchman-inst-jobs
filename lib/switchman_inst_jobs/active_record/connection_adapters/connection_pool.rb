module SwitchmanInstJobs
  module ActiveRecord
    module ConnectionAdapters
      module ConnectionPool
        def shard
          if connection_klass == ::Delayed::Backend::ActiveRecord::AbstractJob
            return shard_stack.last || ::Switchman::Shard.current(::ActiveRecord::Base).delayed_jobs_shard
          end

          super
        end
      end
    end
  end
end
