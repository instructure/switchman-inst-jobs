describe SwitchmanInstJobs::Delayed::Worker::HealthCheck do
  describe '.reschedule_abandoned_jobs' do
    it 'cleans jobs on each shard, but files no jobs' do
      shard1 = Switchman::Shard.create!
      shard1.update_attribute(:delayed_jobs_shard_id, shard1.id)
      shard2 = Switchman::Shard.create!
      shard2.update_attribute(:delayed_jobs_shard_id, shard2.id)

      allow(::SwitchmanInstJobs::Delayed::Settings).to receive(:configured_shard_ids).and_return([shard1.id, shard2.id])
      expect(Delayed::Settings).to receive(:worker_health_check_type).at_least(:once).and_return(:consul)
      health_checker = double(live_workers: [])
      allow(::Delayed::Worker::HealthCheck).to receive(:build).and_return(health_checker)
      expect(Delayed::Job).to receive(:running_jobs).exactly(2).times.and_return([])
      expect(Delayed::Worker::HealthCheck).to receive(:delay).never
      Delayed::Worker::HealthCheck.reschedule_abandoned_jobs
    end
  end

  describe '.munge_service_name' do
    it 'replaces the service name just for the duration of the invoked block' do
      stable = ::Delayed::Settings.worker_health_check_config['service_name']
      shard = Switchman::Shard.create!
      shard.update_attribute(:delayed_jobs_shard_id, shard.id)
      expected_service_name = "inst-jobs_worker/#{shard.id}"
      Delayed::Worker::HealthCheck.munge_service_name(shard) do
        expect(::Delayed::Settings.worker_health_check_config['service_name']).to eq(expected_service_name)
      end
      expect(stable).to_not eq(expected_service_name)
      expect(::Delayed::Settings.worker_health_check_config['service_name']).to eq(stable)
    end
  end
end
