describe SwitchmanInstJobs::JobsMigrator do
  include Switchman::RSpecHelper

  let(:shard1) { @shard1 }

  before do
    # Since we can explicitly clear the cache, this makes specs run in a reasonable length of time
    described_class.instance_variable_set(:@skip_cache_wait, true)
    # Pin the default shard as a jobs shard to ensure the default shard is used as a jobs shard when it is active
    Switchman::Shard.default.delayed_jobs_shard_id = Switchman::Shard.default.id
    Switchman::Shard.default.save!
    shard1.delayed_jobs_shard_id = shard1.id
    shard1.save!
  end

  it "should move strand'd jobs, and not non-strand'd jobs" do
    Switchman::Shard.activate(::ActiveRecord::Base => shard1,
                              ::Delayed::Backend::ActiveRecord::AbstractJob => Switchman::Shard.default) do
      expect(Switchman::Shard.current(::Delayed::Backend::ActiveRecord::AbstractJob)).to eq Switchman::Shard.default
      5.times { Kernel.delay(strand: 'strand1').sleep(0.1) }
      6.times { Kernel.delay(strand: 'strand2').sleep(0.2) }
      7.times { Kernel.delay.sleep(0.3) }
    end
    4.times { Kernel.delay.sleep(0.4) }

    shard1.activate(::ActiveRecord::Base, ::Delayed::Backend::ActiveRecord::AbstractJob) do
      3.times { Kernel.delay(strand: 'strand1').sleep(0.5) }
      expect(Delayed::Job.count).to eq 3
    end

    # 5 + 6 + 7 + 4
    expect(Delayed::Job.count).to eq 22
    # Ensure that shard1 actually *changes* jobs shards
    shard1.delayed_jobs_shard_id = Switchman::Shard.default.id
    shard1.save!
    described_class.migrate_shards({ shard1 => shard1 })
    # 4
    expect(Delayed::Job.count).to eq 4

    shard1.activate(::Delayed::Backend::ActiveRecord::AbstractJob) do
      # 5 + 6 + 3 + 7
      expect(Delayed::Job.count).to eq 21
      # 0.1 jobs come before 0.5 jobs
      strand = Delayed::Job.where(strand: 'strand1')
      first_job = strand.next_in_strand_order.first
      expect(first_job.payload_object.args).to eq [0.1]
      # when the current running job on other shard finishes it will set next_in_strand
      expect(first_job.next_in_strand).to be_falsy
      expect(strand.where(next_in_strand: true).count).to eq 1
    end
  end

  it 'should set block_stranded to false when migration is done even if no jobs moved' do
    described_class.migrate_shards({ shard1 => shard1 })
    expect(shard1.reload.block_stranded).to be_falsy
  end

  it 'should create a blocker strand if a job is currently running' do
    Switchman::Shard.activate(::ActiveRecord::Base => shard1,
                              ::Delayed::Backend::ActiveRecord::AbstractJob => Switchman::Shard.default) do
      5.times { Kernel.delay(strand: 'strand1').sleep(0.1) }
    end
    Delayed::Job.where(shard_id: shard1.id, strand: 'strand1').next_in_strand_order.first.
      update(locked_by: 'specs', locked_at: DateTime.now)

    expect(Delayed::Job.where(strand: 'strand1').count).to eq 5
    described_class.run
    # The currently running job is kept
    expect(Delayed::Job.count).to eq 1

    shard1.activate(::Delayed::Backend::ActiveRecord::AbstractJob) do
      strand = Delayed::Job.where(strand: 'strand1')
      # There should be the 4 non-running jobs + 1 blocker
      expect(strand.count).to eq 5
      first_job = strand.next_in_strand_order.first
      expect(first_job.source).to eq 'JobsMigrator::StrandBlocker'
      # when the current running job on other shard finishes it will set next_in_strand
      expect(first_job.next_in_strand).to be_falsy
      expect(strand.where(next_in_strand: true).count).to eq 0
    end
  end

  it 'should handle pre-existing (or migrated earlier in the run) singleton jobs gracefully' do
    Switchman::Shard.activate(::ActiveRecord::Base => shard1,
                              ::Delayed::Backend::ActiveRecord::AbstractJob => Switchman::Shard.default) do
      Kernel.delay(singleton: 'singleton1').sleep(0.1)
    end
    shard1.activate do
      Kernel.delay(singleton: 'singleton1').sleep(0.1)
    end

    expect(Delayed::Job.where(singleton: 'singleton1').count).to eq 1
    shard1.activate(::Delayed::Backend::ActiveRecord::AbstractJob) do
      expect(Delayed::Job.where(singleton: 'singleton1').count).to eq 1
    end
    described_class.run
    # The singleton was dropped from this shard
    expect(Delayed::Job.where(singleton: 'singleton1').count).to eq 0

    # There is still one singleton on the new shard
    shard1.activate(::Delayed::Backend::ActiveRecord::AbstractJob) do
      expect(Delayed::Job.where(singleton: 'singleton1').count).to eq 1
    end
  end

  context 'before_move_callbacks' do
    it 'Should pass the original job record to a callback' do
      @old_job = nil
      # rubocop:todo Lint/UnusedBlockArgument
      described_class.add_before_move_callback(->(old_job:, new_job:) { @old_job = old_job })
      # rubocop:enable Lint/UnusedBlockArgument
      Switchman::Shard.activate(::ActiveRecord::Base => shard1,
                                ::Delayed::Backend::ActiveRecord::AbstractJob => Switchman::Shard.default) do
        Kernel.delay(strand: 'strand', ignore_transaction: true).sleep(0)
      end
      described_class.run
      expect(@old_job.shard).to eq(Switchman::Shard.default)
    end

    it 'Should pass the new job record to a callback' do
      @new_job = nil
      # rubocop:todo Lint/UnusedBlockArgument
      described_class.add_before_move_callback(->(old_job:, new_job:) { @new_job = new_job })
      # rubocop:enable Lint/UnusedBlockArgument
      Switchman::Shard.activate(::ActiveRecord::Base => shard1,
                                ::Delayed::Backend::ActiveRecord::AbstractJob => Switchman::Shard.default) do
        Kernel.delay(strand: 'strand', ignore_transaction: true).sleep(0)
      end
      described_class.run
      expect(@new_job.shard).to eq(shard1)
    end

    it 'Should call before the new job record is saved' do
      @new_job = nil
      # rubocop:todo Lint/UnusedBlockArgument
      described_class.add_before_move_callback(->(old_job:, new_job:) { @new_job = new_job })
      # rubocop:enable Lint/UnusedBlockArgument
      Switchman::Shard.activate(::ActiveRecord::Base => shard1,
                                ::Delayed::Backend::ActiveRecord::AbstractJob => Switchman::Shard.default) do
        Kernel.delay(strand: 'strand', ignore_transaction: true).sleep(0)
      end
      described_class.run
      expect(@new_job.new_record?).to be true
    end
  end
end
