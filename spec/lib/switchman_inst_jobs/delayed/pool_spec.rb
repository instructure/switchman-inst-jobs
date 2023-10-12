# frozen_string_literal: true

describe SwitchmanInstJobs::Delayed::Pool do
  include Switchman::RSpecHelper

  let(:shard) { @shard1 }
  let(:worker) { Delayed::Worker.new(worker_max_job_count: 1, shard: shard.id) }

  describe "pools" do
    it "prevents creation of pools with workers in other regions" do
      expect(Switchman::Shard).to receive(:lookup).with(shard.id).and_return(shard)
      expect(shard).to receive(:in_current_region?).and_return(false)

      expect { Delayed::Pool.new({ workers: [{ shard: shard.id }] }) }.to raise_error("Cannot run jobs cross-region")
    end

    it "should unlock against the worker's shard" do
      allow(Delayed::Job).to receive(:unlock_orphaned_jobs) do
        expect(Switchman::Shard.current(Delayed::Backend::ActiveRecord::AbstractJob))
          .to eq Switchman::Shard.default.delayed_jobs_shard
        0
      end
      Delayed::Pool.new({ workers: [] }).send(
        :unlock_orphaned_jobs, Delayed::Worker.new, 1234
      )

      allow(Delayed::Job).to receive(:unlock_orphaned_jobs) do
        expect(Switchman::Shard.current(Delayed::Backend::ActiveRecord::AbstractJob)).to eq shard
        0
      end
      Delayed::Pool.new({ workers: [] }).send(:unlock_orphaned_jobs, worker, 1234)
    end

    it "should unlock against all configured shards" do
      pool = Delayed::Pool.new({ workers: [] })
      pool.instance_variable_set(
        :@config,
        workers: [
          { shard: shard.id }
        ]
      )

      allow(Delayed::Job).to receive(:unlock_orphaned_jobs) do
        expect(Switchman::Shard.current(Delayed::Backend::ActiveRecord::AbstractJob)).to eq shard
        0
      end
      pool.send(:unlock_orphaned_jobs)

      pool.instance_variable_set(
        :@config,
        workers: [
          {},
          {},
          { shard: shard.id },
          { shard: shard.id }
        ]
      )

      shards = []
      allow(Delayed::Job).to receive(:unlock_orphaned_jobs) do
        shards << Switchman::Shard.current(Delayed::Backend::ActiveRecord::AbstractJob)
        0
      end
      pool.send(:unlock_orphaned_jobs)

      expect(shards.sort_by(&:id)).to eq [
        Switchman::Shard.default.delayed_jobs_shard,
        shard
      ]
    end
  end
end
