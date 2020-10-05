module SwitchmanInstJobs
  class ShardNotFoundError < RuntimeError
    attr_reader :shard_id

    def initialize(shard_id)
      @shard_id = shard_id
      super("Shard not found: #{shard_id}")
    end
  end

  module Delayed
    module Backend
      module Base
        module ClassMethods
          def enqueue(object, options = {})
            ::Switchman::Shard.periodic_clear_shard_cache
            current_shard = ::Switchman::Shard.current
            enqueue_options = options.merge(
              current_shard: current_shard
            )
            enqueue_job = -> { ::GuardRail.activate(:master) { super(object, enqueue_options) } }

            # Another dj shard must be currently manually activated, so just use that
            # In general this will only happen in unusual circumstances like tests
            # also if migrations are running, always use the current shard's job shard
            if ::ActiveRecord::Migration.open_migrations.zero? &&
               current_shard.delayed_jobs_shard != ::Switchman::Shard.current(:delayed_jobs)
              enqueue_job.call
            else
              ::Switchman::Shard.default.activate do
                current_shard = ::Switchman::Shard.lookup(current_shard.id)
              end
              current_job_shard = current_shard.delayed_jobs_shard

              if (options[:singleton] || options[:strand]) && current_shard.block_stranded
                enqueue_options[:next_in_strand] = false
              end

              current_job_shard.activate(:delayed_jobs) do
                enqueue_job.call
              end
            end
          end

          def configured_shard_ids
            (::Delayed::Settings.worker_config.try(:[], 'workers') || [])
              .map { |w| w['shard'] }.compact.uniq
          end

          def processes_locked_locally
            shard_ids = configured_shard_ids
            if shard_ids.any?
              shards = shard_ids.map { |shard_id| ::Delayed::Worker.shard(shard_id) }
              ::Switchman::Shard.with_each_shard(shards, [:delayed_jobs]) do
                super
              end
            else
              super
            end
          end
        end

        def self.prepended(base)
          base.singleton_class.prepend(ClassMethods)
          base.shard_category = :delayed_jobs if base.name == 'Delayed::Backend::ActiveRecord::Job'
        end

        def current_shard
          @current_shard ||= ::Switchman::Shard.lookup(shard_id)
        end

        def current_shard=(shard)
          @current_shard = nil
          self.shard_id = shard.id
          self.shard_id = nil if shard.is_a?(::Switchman::DefaultShard)
          # If jobs are held for a shard, enqueue new ones as held as well
          return unless shard.jobs_held

          self.locked_by = ::Delayed::Backend::Base::ON_HOLD_LOCKED_BY
          self.locked_at = ::Delayed::Job.db_time_now
          self.attempts = ::Delayed::Backend::Base::ON_HOLD_COUNT
        end

        def invoke_job
          current_shard.activate { super }
        end

        def deserialize(source)
          raise ShardNotFoundError, shard_id unless current_shard

          current_shard.activate { super }
        rescue ::Switchman::ConnectionError, PG::ConnectionBad, PG::UndefinedTable
          # likely a missing shard with a stale cache
          current_shard.send(:clear_cache)
          ::Switchman::Shard.clear_cache
          raise ShardNotFoundError, shard_id unless ::Switchman::Shard.where(id: shard_id).exists?

          raise
        end
      end
    end
  end
end
