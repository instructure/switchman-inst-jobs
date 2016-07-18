describe SwitchmanInstJobs::Switchman::DefaultShard do
  describe '#delayed_jobs_shard' do
    it 'always uses own shard for jobs' do
      jobs_shard = ::Switchman::Shard.default.delayed_jobs_shard
      expect(jobs_shard).to eq ::Switchman::Shard.default
    end
  end
end
