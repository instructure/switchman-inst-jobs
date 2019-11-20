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
        database_server&.delayed_jobs_shard(self)
      end

      module ClassMethods
        def clear_cache
          super
          remove_instance_variable(:@delayed_jobs_shards) if instance_variable_defined?(:@delayed_jobs_shards)
        end

        def current(category = :primary)
          if category == :delayed_jobs
            active_shards[category] || super(:primary).delayed_jobs_shard
          else
            super
          end
        end

        def activate!(categories)
          if !@skip_delayed_job_auto_activation &&
             !categories[:delayed_jobs] &&
             categories[:primary] &&
             categories[:primary] != active_shards[:primary]
            skip_delayed_job_auto_activation do
              categories[:delayed_jobs] =
                categories[:primary].delayed_jobs_shard
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

        def create
          db = ::Switchman::DatabaseServer.server_for_new_shard
          db.create_new_shard
        end

        def delayed_jobs_shards
          unless instance_variable_defined?(:@delayed_jobs_shards)
            # re-entrancy protection
            @delayed_jobs_shards = begin
              shard_dj_shards = [] unless ::Switchman::Shard.columns_hash.key?('delayed_jobs_shard_id')
              shard_dj_shards ||= begin
                ::Switchman::Shard
                  .where.not(delayed_jobs_shard_id: nil)
                  .distinct
                  .pluck(:delayed_jobs_shard_id)
                  .map { |id| ::Switchman::Shard.lookup(id) }
                  .compact
              end
              # set it temporarily, to avoid the default shard falling back to itself
              # if other shards are usable
              @delayed_jobs_shards = shard_dj_shards.uniq.sort

              db_dj_shards = ::Switchman::DatabaseServer.all.map do |db|
                next db.shards.to_a if db.config[:delayed_jobs_shard] == 'self'
                db.delayed_jobs_shard
              end.compact.flatten.uniq # yes, all three

              (db_dj_shards + shard_dj_shards).uniq.sort
            end
          end
          @delayed_jobs_shards
        end
      end
    end
  end
end
