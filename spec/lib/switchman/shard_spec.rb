describe SwitchmanInstJobs::Switchman::Shard do
  include Switchman::RSpecHelper

  let(:shard) { @shard1 }
  let(:jobs_shard) { @shard2 }

  describe '#clear_cache' do
    it 'triggers cache clear after transaction'
  end

  describe '#delayed_jobs_shard' do
    it 'returns configured jobs shard' do
      shard.update delayed_jobs_shard_id: jobs_shard.id
      expect(shard.delayed_jobs_shard).to eq jobs_shard
    end

    it 'returns the DB server delayed jobs shard' do
      shard = Switchman::Shard.new
      shard.database_server = Switchman::DatabaseServer.new(
        'jobs1', delayed_jobs_shard: jobs_shard.id
      )
      expect(shard.delayed_jobs_shard).to eq jobs_shard
    end

    it 'returns another dj shard for the default shard' do
      skip 'broken on newer rubies when un-stubbing the prepended class method'
      expect(Switchman::Shard).to receive(:delayed_jobs_shards).
        at_least(1).
        and_return([jobs_shard])
      expect(shard.delayed_jobs_shard).to eq jobs_shard
    end
  end

  describe '.current' do
    it 'return default shard delayed_jobs_shard' do
      expect(
        Switchman::Shard.current(Delayed::Backend::ActiveRecord::AbstractJob)
      ).to eq Switchman::Shard.default
    end
  end

  describe '.delayed_jobs_shards' do
    it "returns just the default shard when there's no other config" do
      expect(Switchman::Shard.delayed_jobs_shards).to eq [Switchman::Shard.default]
    end

    it 'returns a referenced shard' do
      shard1 = Switchman::Shard.create!
      shard2 = Switchman::Shard.create!
      shard1.update!(delayed_jobs_shard_id: shard2.id)
      if Switchman::Shard.instance_variable_defined?(:@jobs_scope_empty)
        Switchman::Shard.remove_instance_variable(:@jobs_scope_empty)
      end
      expect(Switchman::Shard.delayed_jobs_shards).to eq [shard2].sort
    end
  end

  it 'should use lookup instead of find when deserializing shards' do
    job = shard.delay(ignore_transaction: true).id
    allow(job).to receive(:current_shard).and_return(Switchman::Shard.current) # load current_shard
    expect(Switchman::Shard).to receive(:lookup).with(shard.id.to_s).and_return(shard)
    job.instance_variable_set(:@payload_object, nil)
    job.payload_object
  end

  describe '#hold_jobs!' do
    it 'locks existing jobs' do
      job = Kernel.delay(ignore_transaction: true).sleep
      Switchman::Shard.default.hold_jobs!(wait: true)
      expect(job.reload.locked_by).to eq Delayed::Backend::Base::ON_HOLD_LOCKED_BY
    end
  end

  describe '#unhold_jobs!' do
    it 'unholds existing jobs' do
      job = Kernel.delay(ignore_transaction: true).sleep
      job.hold!
      Switchman::Shard.default.unhold_jobs!
      expect(job.reload.locked_by).to be_nil
    end
  end
end
