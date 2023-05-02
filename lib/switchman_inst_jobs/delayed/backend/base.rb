# frozen_string_literal: true

module SwitchmanInstJobs
  class ShardNotFoundError < RuntimeError
    attr_reader :shard_id

    def initialize(shard_id)
      @shard_id = shard_id
      super("Shard not found: #{shard_id}")
    end
  end

  class JobsBlockedError < RuntimeError
  end

  module Delayed
    module Backend
      module Base
        module ClassMethods
          def enqueue(object, **options)
            ::Switchman::Shard.periodic_clear_shard_cache
            current_shard = options[:current_shard] || ::Switchman::Shard.current
            enqueue_options = options.merge(
              current_shard: current_shard
            )
            enqueue_job = -> { ::GuardRail.activate(:primary) { super(object, **enqueue_options) } }

            # Another dj shard must be currently manually activated, so just use that
            # In general this will only happen in unusual circumstances like tests
            # also if migrations are running, always use the current shard's job shard
            if ::ActiveRecord::Migration.open_migrations.zero? &&
               current_shard.delayed_jobs_shard !=
               ::Switchman::Shard.current(::Delayed::Backend::ActiveRecord::AbstractJob)
              enqueue_job.call
            else
              current_shard = ::Switchman::Shard.lookup(current_shard.id)
              current_job_shard = current_shard.delayed_jobs_shard

              if (options[:singleton] || options[:strand]) && current_shard.block_stranded
                enqueue_options[:next_in_strand] = false
              end

              current_shard.activate do
                current_job_shard.activate(::Delayed::Backend::ActiveRecord::AbstractJob) do
                  enqueue_job.call
                end
              end
            end
          end

          def configured_shard_ids
            ::SwitchmanInstJobs::Delayed::Settings.configured_shard_ids
          end

          def processes_locked_locally
            shard_ids = configured_shard_ids
            if shard_ids.any?
              shards = shard_ids.map { |shard_id| ::Delayed::Worker.shard(shard_id) }
              ::Switchman::Shard.with_each_shard(shards, [::Delayed::Backend::ActiveRecord::AbstractJob]) do
                super
              end
            else
              super
            end
          end
        end

        def self.prepended(base)
          base.singleton_class.prepend(ClassMethods)
          return unless base.name == "Delayed::Backend::ActiveRecord::Job"

          ::Delayed::Backend::ActiveRecord::AbstractJob.sharded_model
        end

        def current_shard
          @current_shard ||= ::Switchman::Shard.lookup(shard_id)
        end

        def current_shard=(shard)
          @current_shard = nil
          self.shard_id = shard.id
          self.shard_id = nil if shard.is_a?(::Switchman::DefaultShard)
          # If jobs are held for a shard, enqueue new ones as held as well
          return unless ::Switchman::Shard.columns_hash.key?("jobs_held") && shard.jobs_held

          self.locked_by = ::Delayed::Backend::Base::ON_HOLD_LOCKED_BY
          self.locked_at = ::Delayed::Job.db_time_now
          self.attempts = ::Delayed::Backend::Base::ON_HOLD_COUNT
        end

        def invoke_job
          raise ShardNotFoundError, shard_id unless current_shard

          current_shard.activate { super }
        end

        def deserialize(source)
          raise ShardNotFoundError, shard_id unless current_shard

          current_shard.activate { super }
        rescue PG::ConnectionBad, PG::UndefinedTable
          # likely a missing shard with a stale cache
          current_shard.send(:clear_cache)
          ::Switchman::Shard.clear_cache
          raise ShardNotFoundError, shard_id unless ::Switchman::Shard.exists?(id: shard_id)

          raise
        end
      end
    end
  end
end
