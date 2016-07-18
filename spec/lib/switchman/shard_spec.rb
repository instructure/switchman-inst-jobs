describe SwitchmanInstJobs::Switchman::Shard do
  let(:shard) { ::Switchman::Shard.create }
  let(:jobs_shard) { ::Switchman::Shard.create }

  describe '#clear_cache' do
    it 'triggers cache clear after transaction'
  end

  describe '#delayed_jobs_shard' do
    it 'returns configured jobs shard' do
      shard.update delayed_jobs_shard_id: jobs_shard.id
      expect(shard.delayed_jobs_shard).to eq jobs_shard
    end

    it 'returns the DB server delayed jobs shard' do
      shard.database_server = ::Switchman::DatabaseServer.new(
        'jobs1', delayed_jobs_shard: jobs_shard.id
      )
      expect(shard.delayed_jobs_shard).to eq jobs_shard
    end
  end

  describe '.current' do
    it 'returns active :delayed_jobs shard' do
      expect(::Switchman::Shard).to receive(:active_shards).once.and_return(
        delayed_jobs: jobs_shard
      )

      expect(::Switchman::Shard.current(:delayed_jobs)).to eq jobs_shard
    end

    it 'return default shard delayed_jobs_shard' do
      expect(
        ::Switchman::Shard.current(:delayed_jobs)
      ).to eq ::Switchman::Shard.default
    end
  end

  describe '.create' do
    it 'uses DatabaseServer to configure new shard' do
      expect(::Switchman::DatabaseServer)
        .to receive(:server_for_new_shard).once.and_call_original
      ::Switchman::Shard.create
    end

    it 'creates a new shard' do
      expect do
        ::Switchman::Shard.create
      end.to change { ::Switchman::Shard.count }.by 1
    end
  end
end
