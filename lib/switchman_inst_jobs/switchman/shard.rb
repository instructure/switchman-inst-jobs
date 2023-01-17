module SwitchmanInstJobs
  module Switchman
    module Shard
      def self.prepended(base)
        base.singleton_class.prepend(ClassMethods)
      end

      def clear_cache
        self.class.connection.after_transaction_commit { super }
      end

      def delayed_jobs_shard
        if read_attribute(:delayed_jobs_shard_id)
          shard = ::Switchman::Shard.lookup(delayed_jobs_shard_id)
          return shard if shard
        end
        @delayed_jobs_shard ||= database_server&.delayed_jobs_shard(self)
      end

      # Adapted from hold/unhold methods in base delayed jobs base
      # Wait is required to be able to safely move jobs
      def hold_jobs!(wait: false)
        self.jobs_held = true
        save! if changed?
        delayed_jobs_shard.activate(::Delayed::Backend::ActiveRecord::AbstractJob) do
          lock_jobs_for_hold
        end
        return unless wait

        delayed_jobs_shard.activate(::Delayed::Backend::ActiveRecord::AbstractJob) do
          while ::Delayed::Job.where(shard_id: id).
              where.not(locked_at: nil).
              where.not(locked_by: ::Delayed::Backend::Base::ON_HOLD_LOCKED_BY).exists?
            sleep 10
            lock_jobs_for_hold
          end
        end
      end

      def unhold_jobs!
        self.jobs_held = false
        if changed?
          save!
          # Wait a little over the 60 second in-process shard cache clearing
          # threshold to ensure that all new jobs are now being enqueued
          # unlocked
          Rails.logger.debug('Waiting for caches to clear')
          sleep(65)
        end
        delayed_jobs_shard.activate(::Delayed::Backend::ActiveRecord::AbstractJob) do
          ::Delayed::Job.where(locked_by: ::Delayed::Backend::Base::ON_HOLD_LOCKED_BY, shard_id: id).
            in_batches(of: 10_000).
            update_all(
              locked_by: nil,
              locked_at: nil,
              attempts: 0,
              failed_at: nil
            )
        end
      end

      private

      def lock_jobs_for_hold
        ::Delayed::Job.where(locked_at: nil, shard_id: id).in_batches(of: 10_000).update_all(
          locked_by: ::Delayed::Backend::Base::ON_HOLD_LOCKED_BY,
          locked_at: ::Delayed::Job.db_time_now,
          attempts: ::Delayed::Backend::Base::ON_HOLD_COUNT
        )
      end

      module ClassMethods
        def clear_cache
          super
          remove_instance_variable(:@delayed_jobs_shards) if instance_variable_defined?(:@delayed_jobs_shards)
        end

        def activate!(categories)
          if !@skip_delayed_job_auto_activation &&
             !categories[::Delayed::Backend::ActiveRecord::AbstractJob] &&
             categories[::ActiveRecord::Base] &&
             categories[::ActiveRecord::Base] != ::Switchman::Shard.current(::ActiveRecord::Base)
            skip_delayed_job_auto_activation do
              categories[::Delayed::Backend::ActiveRecord::AbstractJob] =
                categories[::ActiveRecord::Base].delayed_jobs_shard
            end
          end
          super
        end

        def skip_delayed_job_auto_activation
          was = @skip_delayed_job_auto_activation
          @skip_delayed_job_auto_activation = true
          yield
        ensure
          @skip_delayed_job_auto_activation = was
        end

        def periodic_clear_shard_cache
          # TODO: make this configurable
          @timed_cache ||= TimedCache.new(-> { 60.to_i.seconds.ago }) do
            ::Switchman::Shard.clear_cache
          end
          @timed_cache.clear
        end

        def delayed_jobs_shards
          return none unless ::Switchman::Shard.columns_hash.key?('delayed_jobs_shard_id')

          scope = ::Switchman::Shard.unscoped.
            where(id: ::Switchman::Shard.unscoped.distinct.where.not(delayed_jobs_shard_id: nil).
            select(:delayed_jobs_shard_id))
          db_jobs_shards = ::Switchman::DatabaseServer.all.map { |db| db.config[:delayed_jobs_shard] }.uniq
          db_jobs_shards.delete(nil)
          has_self = db_jobs_shards.delete('self')
          scope = scope.or(::Switchman::Shard.unscoped.where(id: db_jobs_shards)) unless db_jobs_shards.empty?

          if has_self
            self_dbs = ::Switchman::DatabaseServer.all.
              select { |db| db.config[:delayed_jobs_shard] == 'self' }.map(&:id)
            scope = scope.or(::Switchman::Shard.unscoped.
              where(id: ::Switchman::Shard.unscoped.where(delayed_jobs_shard_id: nil, database_server_id: self_dbs).
              select(:id)))
          end
          @jobs_scope_empty = !scope.exists? unless instance_variable_defined?(:@jobs_scope_empty)
          return ::Switchman::Shard.where(id: ::Switchman::Shard.default.id) if @jobs_scope_empty

          ::Switchman::Shard.merge(scope)
        end
      end
    end
  end
end
