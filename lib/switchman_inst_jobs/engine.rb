module SwitchmanInstJobs
  class Engine < ::Rails::Engine
    isolate_namespace SwitchmanInstJobs

    initializer 'sharding.active_record', after: 'switchman.extend_connection_adapters' do
      SwitchmanInstJobs.initialize_active_record
    end

    initializer 'sharding.delayed' do
      SwitchmanInstJobs.initialize_inst_jobs

      ::Delayed::Worker.lifecycle.around(:work_queue_pop) do |worker, config, &block|
        if config[:shard]
          ::Switchman::Shard.lookup(config[:shard]).activate(:delayed_jobs) { block.call(worker, config) }
        else
          block.call(worker, config)
        end
      end
    end

    initializer 'sharding.shackles', after: 'switchman.extend_shackles' do
      SwitchmanInstJobs.initialize_shackles
    end

    initializer 'sharding.switchman' do
      SwitchmanInstJobs.initialize_switchman
    end

    config.after_initialize do
      ::Switchman::Shard.default.delayed_jobs_shard.activate!(:delayed_jobs)
    end
  end
end
