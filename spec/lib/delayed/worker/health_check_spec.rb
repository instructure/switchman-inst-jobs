describe SwitchmanInstJobs::Delayed::Worker::HealthCheck do
  describe '.reschedule_abandoned_jobs' do
    it "just calls super if there's only one jobs shard" do
      expect(Delayed::Settings).to receive(:worker_health_check_type).and_return(:consul).twice
      expect_any_instance_of(Delayed::Worker::ConsulHealthCheck)
        .to receive(:live_workers).and_return([])
      expect(Switchman::Shard).to receive(:with_each_shard).never

      expect(Delayed::Job).to receive(:running_jobs).once.and_return([])
      Delayed::Worker::HealthCheck.reschedule_abandoned_jobs
    end

    it 'schedules a separate job for each jobs shard' do
      shard1 = Switchman::Shard.create!
      shard1.update_attribute(:delayed_jobs_shard_id, shard1.id)
      shard2 = Switchman::Shard.create!
      shard2.update_attribute(:delayed_jobs_shard_id, shard2.id)

      ran_on_shards = []
      expect(Delayed::Job).to receive(:running_jobs).never
      expect(Delayed::Worker::HealthCheck).to receive(:delay).twice do
        ran_on_shards << Switchman::Shard.current(:delayed_jobs)
      end
      Delayed::Worker::HealthCheck.reschedule_abandoned_jobs
      expect(ran_on_shards).to eq [shard1, shard2].sort
    end
  end
end
