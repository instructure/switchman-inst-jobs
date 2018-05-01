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
            original_service_name = ::Delayed::Settings.worker_health_check_config['service_name']
            ::Delayed::Settings.worker_health_check_config['service_name'] = "#{original_service_name || ::Delayed::Worker::ConsulHealthCheck::DEFAULT_SERVICE_NAME}/#{shard.id}"
            yield
          ensure
            ::Delayed::Settings.worker_health_check_config['service_name'] = original_service_name
          end

          def reschedule_abandoned_jobs(call_super: false)
            shards = ::Switchman::Shard.delayed_jobs_shards
            call_super = true if shards.length == 1
            return munge_service_name(::Switchman::Shard.current(:delayed_jobs)) { super() } if call_super

            ::Switchman::Shard.with_each_shard(shards, [:delayed_jobs]) do
              self.send_later_enqueue_args(:reschedule_abandoned_jobs,
                                           { singleton: "periodic: Delayed::Worker::HealthCheck.reschedule_abandoned_jobs:#{::Switchman::Shard.current(:delayed_jobs).id}" },
                                           call_super: true)
            end
          end
        end
      end
    end
  end
end
