# frozen_string_literal: true

module SwitchmanInstJobs
  class Engine < ::Rails::Engine
    isolate_namespace SwitchmanInstJobs

    initializer "sharding.active_record", after: "switchman.extend_connection_adapters" do
      SwitchmanInstJobs.initialize_active_record
    end

    initializer "sharding.delayed" do
      SwitchmanInstJobs.initialize_inst_jobs

      ::Delayed::Worker.lifecycle.around(:work_queue_pop) do |worker, config, &block|
        if config[:shard]
          ::Switchman::Shard.lookup(config[:shard]).activate(::Delayed::Backend::ActiveRecord::AbstractJob) do
            block.call(worker, config)
          end
        else
          block.call(worker, config)
        end
      end

      # Ensure jobs get unblocked on the new shard if they exist
      ::Delayed::Worker.lifecycle.after(:perform) do |_worker, job|
        if job.strand || job.singleton
          column = job.strand ? :strand : :singleton

          ::Switchman::Shard.clear_cache
          ::Switchman::Shard.default.activate do
            current_job_shard = ::Switchman::Shard.lookup(job.shard_id).delayed_jobs_shard
            if current_job_shard != ::Switchman::Shard.current(::Delayed::Backend::ActiveRecord::AbstractJob)
              current_job_shard.activate(::Delayed::Backend::ActiveRecord::AbstractJob) do
                ::Delayed::Job.where(source: "JobsMigrator::StrandBlocker", **{ column => job.try(column) }).delete_all

                j = ::Delayed::Job.where(**{ column => job.try(column) }).next_in_strand_order.first
                j.update_column(:next_in_strand, true) if j && !j.next_in_strand
              end
            end
          end
        end
      end
    end

    initializer "sharding.guard_rail", after: "switchman.extend_guard_rail" do
      SwitchmanInstJobs.initialize_guard_rail
    end

    initializer "sharding.switchman" do
      SwitchmanInstJobs.initialize_switchman
    end

    config.after_initialize do
      ::Switchman::Shard.default.delayed_jobs_shard.activate!(::Delayed::Backend::ActiveRecord::AbstractJob)
    end
  end
end
