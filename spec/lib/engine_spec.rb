describe SwitchmanInstJobs::Engine do
  context 'with multiple job shards' do
    let(:shard1) { Switchman::Shard.create }
    let(:shard2) { Switchman::Shard.create }
    let(:work_queue) { Delayed::WorkQueue::InProcess.new }
    let(:worker_config1) { { shard: shard1.id, queue: 'test1' } }
    let(:worker_config2) { { shard: shard2.id, queue: 'test2' } }
    let(:args1) { ['worker_name1', worker_config1] }
    let(:args2) { ['worker_name2', worker_config2] }

    it 'activates the configured job shard1 to pop jobs' do
      expect(Delayed::Job).to receive(:get_and_lock_next_available).
        once.with('worker_name1', 'test1', nil, nil) do
        expect(Switchman::Shard.current(:delayed_jobs)).to eq shard1
        nil
      end
      work_queue.get_and_lock_next_available(*args1)
    end

    it 'activates the configured job shard2 to pop jobs' do
      expect(Delayed::Job).to receive(:get_and_lock_next_available).
        once.with('worker_name2', 'test2', nil, nil) do
        expect(Switchman::Shard.current(:delayed_jobs)).to eq shard2
        nil
      end
      work_queue.get_and_lock_next_available(*args2)
    end
  end
end
