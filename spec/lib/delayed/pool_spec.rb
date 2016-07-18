describe SwitchmanInstJobs::Delayed::Pool do
  let(:shard) { Switchman::Shard.create }
  let(:worker) { Delayed::Worker.new(worker_max_job_count: 1, shard: shard.id) }

  describe 'pools' do
    it "should unlock against the worker's shard" do
      allow(Delayed::Job).to receive(:unlock_orphaned_jobs) do
        expect(Switchman::Shard.current(:delayed_jobs))
          .to eq Switchman::Shard.default.delayed_jobs_shard
        0
      end
      Delayed::Pool.new({}).send(
        :unlock_orphaned_jobs, Delayed::Worker.new, 1234
      )

      allow(Delayed::Job).to receive(:unlock_orphaned_jobs) do
        expect(Switchman::Shard.current(:delayed_jobs)).to eq shard
        0
      end
      Delayed::Pool.new({}).send(:unlock_orphaned_jobs, worker, 1234)
    end

    it 'should unlock against all configured shards' do
      pool = Delayed::Pool.new({})
      pool.instance_variable_set(
        :@config,
        workers: [
          { shard: shard.id }
        ]
      )

      allow(Delayed::Job).to receive(:unlock_orphaned_jobs) do
        expect(Switchman::Shard.current(:delayed_jobs)).to eq shard
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
        shards << Switchman::Shard.current(:delayed_jobs)
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
