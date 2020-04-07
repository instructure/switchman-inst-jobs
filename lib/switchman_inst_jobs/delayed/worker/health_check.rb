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
            consul_service_name = ::Delayed::Worker::ConsulHealthCheck::DEFAULT_SERVICE_NAME
            ::Delayed::Settings.worker_health_check_config['service_name'] =
              "#{original_service_name || consul_service_name}/#{shard.id}"
            yield
          ensure
            ::Delayed::Settings.worker_health_check_config['service_name'] = original_service_name
          end

          def reschedule_abandoned_jobs(call_super: false)
            shards = ::Switchman::Shard.delayed_jobs_shards
            call_super = shards.first if shards.length == 1
            unless call_super == false
              call_super.activate(:delayed_jobs) do
                return munge_service_name(call_super) { super() }
              end
            end

            ::Switchman::Shard.with_each_shard(shards, [:delayed_jobs], exception: :ignore) do
              shard = ::Switchman::Shard.current(:delayed_jobs)
              singleton = <<~SINGLETON
                periodic: Delayed::Worker::HealthCheck.reschedule_abandoned_jobs:#{shard.id}
              SINGLETON
              send_later_enqueue_args(
                :reschedule_abandoned_jobs, { singleton: singleton }, call_super: shard
              )
            end
          end
        end
      end
    end
  end
end
