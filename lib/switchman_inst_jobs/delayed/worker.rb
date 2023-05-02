# frozen_string_literal: true

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
          # ensure we get our own copy of the munged config
          @health_check_config = @health_check_config.dup
        end
      end

      def start
        shard.activate(::Delayed::Backend::ActiveRecord::AbstractJob) { super }
      end

      # Worker#run is usually only called from Worker#start, but if the worker
      # is called directly from the console, we want to make sure it still gets
      # the right shard activated.
      def run
        shard.activate(::Delayed::Backend::ActiveRecord::AbstractJob) { super }
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
