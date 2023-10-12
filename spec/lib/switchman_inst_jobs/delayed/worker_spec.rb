# frozen_string_literal: true

describe SwitchmanInstJobs::Delayed::Worker do
  include Switchman::RSpecHelper

  let(:shard) { @shard1 }
  let(:worker) { Delayed::Worker.new(worker_max_job_count: 1, shard: shard.id) }

  describe "workers" do
    it "doesn't allow workers to be created for shards in other regions" do
      expect(Switchman::Shard).to receive(:lookup).with(shard.id).and_return(shard)
      expect(shard).to receive(:in_current_region?).and_return(false)
      expect { worker }.to raise_error("Cannot run jobs cross-region")
    end

    it "should activate the jobs shard when calling run" do
      expect(Delayed::Job).to receive(:get_and_lock_next_available).once do
        expect(Switchman::Shard.current(Delayed::Backend::ActiveRecord::AbstractJob)).to eq shard
        nil
      end
      worker.run
    end

    it "should activate the jobs shard when calling start" do
      expect(Delayed::Job).to receive(:get_and_lock_next_available).once do
        expect(Switchman::Shard.current(Delayed::Backend::ActiveRecord::AbstractJob)).to eq shard
        worker.instance_variable_set(:@exit, true)
        nil
      end
      worker.start
    end

    it "appends current shard to health check service name" do
      Delayed::Settings.worker_health_check_type = :consul
      Delayed::Settings.worker_health_check_config["service_name"] = "inst-jobs"
      worker = Delayed::Worker.new
      expect(worker.health_check.send(:service_name))
        .to eq "inst-jobs/#{Switchman::Shard.default.id}"
      expect(Delayed::Settings.worker_health_check_config["service_name"]).to eq "inst-jobs"
    ensure
      Delayed::Settings.worker_health_check_type = :none
      Delayed::Settings.worker_health_check_config.clear
    end
  end
end
