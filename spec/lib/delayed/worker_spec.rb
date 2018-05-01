describe SwitchmanInstJobs::Delayed::Worker do
  let(:shard) { Switchman::Shard.create }
  let(:worker) { Delayed::Worker.new(worker_max_job_count: 1, shard: shard.id) }

  describe 'workers' do
    it 'should activate the jobs shard when calling run' do
      expect(Delayed::Job).to receive(:get_and_lock_next_available).once do
        expect(Switchman::Shard.current(:delayed_jobs)).to eq shard
        nil
      end
      worker.run
    end

    it 'should activate the jobs shard when calling start' do
      expect(Delayed::Job).to receive(:get_and_lock_next_available).once do
        expect(Switchman::Shard.current(:delayed_jobs)).to eq shard
        worker.instance_variable_set(:@exit, true)
        nil
      end
      worker.start
    end

    it 'appends current shard to health check service name' do
      begin
        Delayed::Settings.worker_health_check_type = :consul
        Delayed::Settings.worker_health_check_config['service_name'] = 'inst-jobs'
        worker = Delayed::Worker.new()
        expect(worker.health_check.send(:service_name)).to eq "inst-jobs/#{Switchman::Shard.default.id}"
        expect(Delayed::Settings.worker_health_check_config['service_name']).to eq 'inst-jobs'
      ensure
        Delayed::Settings.worker_health_check_type = :none
        Delayed::Settings.worker_health_check_config.clear
      end
    end
  end
end
