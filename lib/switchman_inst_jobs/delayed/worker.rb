module SwitchmanInstJobs
  module Delayed
    module Worker
      def self.prepended(base)
        base.singleton_class.prepend(ClassMethods)
      end

      def initialize(options = {})
        # have to initialize this first, so #shard works
        @config = options
        ::Delayed::Worker::HealthCheck.munge_service_name(shard) do
          super
          # ensure to instantiate with the munged config
          health_check
        end
      end

      def start
        shard.activate(:delayed_jobs) { super }
      end

      # Worker#run is usually only called from Worker#start, but if the worker
      # is called directly from the console, we want to make sure it still gets
      # the right shard activated.
      def run
        shard.activate(:delayed_jobs) { super }
      end

      def shard
        self.class.shard(@config[:shard])
      end

      module ClassMethods
        def shard(shard_id)
          if shard_id
            shard = ::Switchman::Shard.lookup(shard_id)
            return shard if shard
          end
          ::Switchman::Shard.default.delayed_jobs_shard
        end
      end
    end
  end
end
