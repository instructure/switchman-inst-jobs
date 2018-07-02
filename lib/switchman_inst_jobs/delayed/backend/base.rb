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
          self.shard_id = shard.id
          self.shard_id = nil if shard.is_a?(::Switchman::DefaultShard)
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
