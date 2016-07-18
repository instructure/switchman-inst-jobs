module SwitchmanInstJobs
  module Delayed
    module Backend
      module Base
        module ClassMethods
          def enqueue(object, options = {})
            enqueue_options = options.merge(
              current_shard: ::Switchman::Shard.current
            )

            if ::ActiveRecord::Migration.open_migrations.positive?
              ::Switchman::Shard.current.delayed_jobs_shard.activate(:delayed_jobs) do
                super(object, enqueue_options)
              end
            else
              super(object, enqueue_options)
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
          self.shard_id = shard.id
          self.shard_id = nil if shard.is_a?(::Switchman::DefaultShard)
        end

        def invoke_job
          current_shard.activate { super }
        end

        def deserialize(source)
          raise "Shard not found: #{shard_id}" unless current_shard
          current_shard.activate { super }
        rescue ::Switchman::ConnectionError, PG::ConnectionBad, PG::UndefinedTable
          # likely a missing shard with a stale cache
          current_shard.send(:clear_cache)
          ::Switchman::Shard.clear_cache
          unless ::Switchman::Shard.where(id: shard_id).exists?
            raise "Shard not found: #{shard_id}"
          end
          raise
        end
      end
    end
  end
end
