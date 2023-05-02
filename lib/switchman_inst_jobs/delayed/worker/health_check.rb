# frozen_string_literal: true

module SwitchmanInstJobs
  module Delayed
    module Worker
      module HealthCheck
        def self.prepended(base)
          base.singleton_class.prepend(ClassMethods)
        end

        module ClassMethods
          def munge_service_name(shard)
            # munge the name to add the current shard
            original_service_name = ::Delayed::Settings.worker_health_check_config["service_name"]
            consul_service_name = ::Delayed::Worker::ConsulHealthCheck::DEFAULT_SERVICE_NAME
            ::Delayed::Settings.worker_health_check_config["service_name"] =
              "#{original_service_name || consul_service_name}/#{shard.id}"
            yield
          ensure
            ::Delayed::Settings.worker_health_check_config["service_name"] = original_service_name
          end

          def reschedule_abandoned_jobs
            shard_ids = ::SwitchmanInstJobs::Delayed::Settings.configured_shard_ids
            shards = shard_ids.map { |shard_id| ::Delayed::Worker.shard(shard_id) }
            ::Switchman::Shard.with_each_shard(shards,
                                               [::ActiveRecord::Base, ::Delayed::Backend::ActiveRecord::AbstractJob]) do
              munge_service_name(::Switchman::Shard.current) do
                # because this rescheduling process is running on every host, we need
                # to make sure that it's functioning for each shard the current
                # host is programmed to interact with, but ONLY for those shards.
                # reading the config lets us iterate over any shards this host should
                # work with and lets us pick the correct service name to identify which
                # hosts are currently alive and valid via the health checks
                super()
              end
            end
          end
        end
      end
    end
  end
end
