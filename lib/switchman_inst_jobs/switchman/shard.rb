# frozen_string_literal: true

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
        ::Switchman::Shard.where(id: self).hold_jobs!(wait: wait)
      end

      def unhold_jobs!
        ::Switchman::Shard.where(id: self).unhold_jobs!
      end

      module ClassMethods
        # Adapted from hold/unhold methods in base delayed jobs base
        # Wait is required to be able to safely move jobs
        def hold_jobs!(wait: false)
          shards = all.to_a
          wait_for_caches = false
          shards.each do |shard|
            shard.jobs_held = true
            if shard.changed?
              shard.save!
              wait_for_caches = true if wait
            end
          end
          shards_by_jobs_shard(shards).each do |jobs_shard, shard_ids|
            jobs_shard.activate(::Delayed::Backend::ActiveRecord::AbstractJob) do
              lock_jobs_for_hold(shard_ids)
            end
          end
          return unless wait

          # Wait a little over the 60 second in-process shard cache clearing
          # threshold to ensure that all new jobs are now being enqueued
          # locked
          Rails.logger.debug("Waiting for caches to clear")
          sleep(65) if wait

          shards_by_jobs_shard(shards).each do |jobs_shard, shard_ids|
            jobs_shard.activate(::Delayed::Backend::ActiveRecord::AbstractJob) do
              while ::Delayed::Job.where(shard_id: shard_ids)
                                  .where.not(locked_at: nil)
                                  .where.not(locked_by: ::Delayed::Backend::Base::ON_HOLD_LOCKED_BY).exists?
                sleep 10
                lock_jobs_for_hold(shard_ids)
              end
            end
          end
        end

        def unhold_jobs!
          shards = all.to_a
          waited = false
          shards.each do |shard|
            shard.jobs_held = false
            next unless shard.changed?

            shard.save!
            next if waited

            # Wait a little over the 60 second in-process shard cache clearing
            # threshold to ensure that all new jobs are now being enqueued
            # unlocked
            Rails.logger.debug("Waiting for caches to clear")
            sleep(65)
            waited = true
          end
          shards_by_jobs_shard(shards).each do |jobs_shard, shard_ids|
            jobs_shard.activate(::Delayed::Backend::ActiveRecord::AbstractJob) do
              ::Delayed::Job.where(locked_by: ::Delayed::Backend::Base::ON_HOLD_LOCKED_BY, shard_id: shard_ids)
                            .in_batches(of: 10_000)
                            .update_all(
                              locked_by: nil,
                              locked_at: nil,
                              attempts: 0,
                              failed_at: nil
                            )
            end
          end
        end

        # Group the given shards by the shard their jobs live on, returning a
        # hash of delayed_jobs_shard => [shard_id, ...]
        private def shards_by_jobs_shard(shards)
          shards.group_by(&:delayed_jobs_shard).transform_values { |group| group.map(&:id) }
        end

        private def lock_jobs_for_hold(shard_ids)
          ::Delayed::Job.where(locked_at: nil, shard_id: shard_ids).in_batches(of: 10_000).update_all(
            locked_by: ::Delayed::Backend::Base::ON_HOLD_LOCKED_BY,
            locked_at: ::Delayed::Job.db_time_now,
            attempts: ::Delayed::Backend::Base::ON_HOLD_COUNT
          )
        end

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
          @timed_cache ||= TimedCache.new(-> { 60.seconds.ago }) do
            ::Switchman::Shard.clear_cache
          end
          @timed_cache.clear
        end

        def delayed_jobs_shards
          return none unless ::Switchman::Shard.columns_hash.key?("delayed_jobs_shard_id")

          scope = ::Switchman::Shard.unscoped
                                    .where(id: ::Switchman::Shard.unscoped
                                                                 .distinct
                                                                 .where.not(delayed_jobs_shard_id: nil)
                                    .select(:delayed_jobs_shard_id))
          db_jobs_shards = ::Switchman::DatabaseServer.all.map { |db| db.config[:delayed_jobs_shard] }.uniq
          db_jobs_shards.delete(nil)
          has_self = db_jobs_shards.delete("self")
          scope = scope.or(::Switchman::Shard.unscoped.where(id: db_jobs_shards)) unless db_jobs_shards.empty?

          if has_self
            self_dbs = ::Switchman::DatabaseServer.select { |db| db.config[:delayed_jobs_shard] == "self" }.map(&:id)
            scope = scope.or(::Switchman::Shard.unscoped
              .where(id: ::Switchman::Shard.unscoped.where(delayed_jobs_shard_id: nil, database_server_id: self_dbs)
              .select(:id)))
          end
          @jobs_scope_empty = !scope.exists? unless instance_variable_defined?(:@jobs_scope_empty)
          return ::Switchman::Shard.where(id: ::Switchman::Shard.default.id) if @jobs_scope_empty

          ::Switchman::Shard.merge(scope)
        end
      end
    end
  end
end
