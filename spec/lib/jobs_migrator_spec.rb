describe SwitchmanInstJobs::JobsMigrator do
  include Switchman::RSpecHelper

  let(:shard1) { @shard1 }

  def activate_source_shard
    Switchman::Shard.activate(::ActiveRecord::Base => shard1,
                              ::Delayed::Backend::ActiveRecord::AbstractJob => Switchman::Shard.default) do
      expect(Switchman::Shard.current(::Delayed::Backend::ActiveRecord::AbstractJob)).to eq Switchman::Shard.default
      yield
    end
  end

  def activate_target_shard
    shard1.activate(::ActiveRecord::Base, ::Delayed::Backend::ActiveRecord::AbstractJob) do
      expect(Switchman::Shard.current(::Delayed::Backend::ActiveRecord::AbstractJob)).to eq shard1
      yield
    end
  end

  before do
    # Since we can explicitly clear the cache, this makes specs run in a reasonable length of time
    described_class.instance_variable_set(:@skip_cache_wait, true)
    # Pin the default shard as a jobs shard to ensure the default shard is used as a jobs shard when it is active
    Switchman::Shard.default.delayed_jobs_shard_id = Switchman::Shard.default.id
    Switchman::Shard.default.save!
    shard1.delayed_jobs_shard_id = shard1.id
    shard1.save!
  end

  context 'unblock_strands' do
    it 'should unblock stranded jobs when block_stranded becomes false' do
      shard1.update!(block_stranded: true)
      activate_target_shard do
        2.times { Kernel.delay(strand: 'strand1').sleep(0.1) }
        2.times { Kernel.delay(strand: 'strand2').sleep(0.2) }

        expect(Delayed::Job.where(next_in_strand: 'f').count).to eq 4
      end

      described_class.unblock_strands(shard1)
      activate_target_shard do
        expect(Delayed::Job.where(next_in_strand: 'f').count).to eq 4
      end

      shard1.update!(block_stranded: false)
      described_class.unblock_strands(shard1)
      activate_target_shard do
        expect(Delayed::Job.where(next_in_strand: 'f').count).to eq 2
      end
    end

    it 'should unblock the strand with the highest priority' do
      shard1.update!(block_stranded: true)
      activate_target_shard do
        Kernel.delay(strand: 'strand1', strand_order_override: -100).sleep(0.1)
        Kernel.delay(strand: 'strand1', strand_order_override: 100).sleep(0.1)
        Kernel.delay(strand: 'strand2', strand_order_override: 100).sleep(0.2)
        Kernel.delay(strand: 'strand2', strand_order_override: -100).sleep(0.2)

        expect(Delayed::Job.where(next_in_strand: 'f').count).to eq 4
      end

      shard1.update!(block_stranded: false)
      described_class.unblock_strands(shard1, batch_size: 1)
      activate_target_shard do
        expect(Delayed::Job.where(strand_order_override: -100, next_in_strand: 't').count).to eq 2
        expect(Delayed::Job.where(strand_order_override: 100, next_in_strand: 'f').count).to eq 2
      end
    end

    it 'should not unblock stranded jobs when a strand blocker job exists' do
      shard1.update!(block_stranded: true)
      activate_target_shard do
        Kernel.delay(strand: 'strand1').sleep(0.1)
        Kernel.delay(strand: 'strand2').sleep(0.2)
        Kernel.delay(strand: 'strand1', source: 'JobsMigrator::StrandBlocker').sleep(0.1)

        expect(Delayed::Job.where(next_in_strand: 'f').count).to eq 3
      end

      shard1.update!(block_stranded: false)
      described_class.unblock_strands(shard1)
      activate_target_shard do
        expect(Delayed::Job.where(next_in_strand: 'f').count).to eq 2
      end
    end

    it 'should not unblock stranded jobs when a job within that strand already has next_in_strand=true' do
      shard1.update!(block_stranded: true)
      activate_target_shard do
        Kernel.delay(strand: 'strand1').sleep(0.1)
        Kernel.delay(strand: 'strand1').sleep(0.1)
        Kernel.delay(strand: 'strand2').sleep(0.2)

        expect(Delayed::Job.where(next_in_strand: 'f').count).to eq 3
      end

      shard1.update!(block_stranded: false)

      activate_target_shard do
        Delayed::Job.where(strand: 'strand1').first.update!(next_in_strand: true)
      end

      described_class.unblock_strands(shard1)
      activate_target_shard do
        expect(Delayed::Job.where(next_in_strand: 'f').count).to eq 1
      end
    end

    it 'should unblock strandless singletons when block_stranded becomes false' do
      shard1.update!(block_stranded: true)
      activate_target_shard do
        Kernel.delay(singleton: 'singleton1').sleep(0.1)
        Kernel.delay(singleton: 'singleton2').sleep(0.2)

        expect(Delayed::Job.where(next_in_strand: 'f').count).to eq 2
      end

      described_class.unblock_strands(shard1)
      activate_target_shard do
        expect(Delayed::Job.where(next_in_strand: 'f').count).to eq 2
      end

      shard1.update!(block_stranded: false)
      described_class.unblock_strands(shard1)
      activate_target_shard do
        expect(Delayed::Job.where(next_in_strand: 'f').count).to eq 0
      end
    end

    it 'should not unblock strandless singletons when a strand blocker job exists' do
      shard1.update!(block_stranded: true)
      activate_target_shard do
        Kernel.delay(locked_by: 'w1', singleton: 'singleton1', source: 'JobsMigrator::StrandBlocker').sleep(0.1)
        Kernel.delay(singleton: 'singleton1').sleep(0.1)
        Kernel.delay(singleton: 'singleton2').sleep(0.2)

        expect(Delayed::Job.where(next_in_strand: 'f').count).to eq 3
      end

      shard1.update!(block_stranded: false)
      described_class.unblock_strands(shard1)
      activate_target_shard do
        expect(Delayed::Job.where(next_in_strand: 'f').count).to eq 2
      end
    end

    it 'should not unblock strandless singletons when another singleton already has next_in_strand=true' do
      shard1.update!(block_stranded: true)
      activate_target_shard do
        Kernel.delay(singleton: 'singleton1').sleep(0.1)
        Kernel.delay(singleton: 'singleton2').sleep(0.1)
        expect(Delayed::Job.where(next_in_strand: 'f').count).to eq 2
      end

      shard1.update!(block_stranded: false)

      activate_target_shard do
        Delayed::Job.where(singleton: 'singleton1').first.update!(locked_by: 'w1', next_in_strand: true)
        Kernel.delay(singleton: 'singleton1').sleep(0.1)
        expect(Delayed::Job.where(next_in_strand: 'f').count).to eq 2
      end

      described_class.unblock_strands(shard1)
      activate_target_shard do
        expect(Delayed::Job.where(next_in_strand: 'f').count).to eq 1
      end
    end
  end

  it "should move strand'd jobs, and not non-strand'd jobs" do
    activate_source_shard do
      5.times { Kernel.delay(strand: 'strand1').sleep(0.1) }
      6.times { Kernel.delay(strand: 'strand2').sleep(0.2) }
      7.times { Kernel.delay.sleep(0.3) }
    end
    4.times { Kernel.delay.sleep(0.4) }

    activate_target_shard do
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

    activate_target_shard do
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

  it 'should move strandless singleton jobs' do
    activate_source_shard do
      Kernel.delay(singleton: 'singleton1').sleep(0.1)
      Kernel.delay(singleton: 'singleton2').sleep(0.2)
    end

    shard1.delayed_jobs_shard_id = Switchman::Shard.default.id
    shard1.save!

    activate_target_shard do
      expect(Delayed::Job.where.not(singleton: nil).count).to eq 0
    end

    described_class.migrate_shards({ shard1 => shard1 })

    activate_target_shard do
      expect(Delayed::Job.where.not(singleton: nil).count).to eq 2
    end
  end

  it 'should not overwrite strandless singleton jobs on the target shard' do
    activate_source_shard do
      Kernel.delay(singleton: 'singleton1').sleep(0.1)
    end

    activate_target_shard do
      Kernel.delay(singleton: 'singleton1').sleep(0.2)
    end

    shard1.delayed_jobs_shard_id = Switchman::Shard.default.id
    shard1.save!

    activate_target_shard do
      expect(Delayed::Job.where.not(singleton: nil).first&.payload_object&.args).to eq [0.2]
    end

    described_class.migrate_shards({ shard1 => shard1 })

    activate_target_shard do
      expect(Delayed::Job.where.not(singleton: nil).first&.payload_object&.args).to eq [0.2]
    end
  end

  it 'should set block_stranded to false when migration is done even if no jobs moved' do
    described_class.migrate_shards({ shard1 => shard1 })
    expect(shard1.reload.block_stranded).to be_falsy
  end

  it 'should create a blocker strand if a job is currently running' do
    activate_source_shard do
      5.times { Kernel.delay(strand: 'strand1').sleep(0.1) }
    end
    Delayed::Job.where(shard_id: shard1.id, strand: 'strand1').next_in_strand_order.first.
      update(locked_by: 'specs', locked_at: DateTime.now)

    expect(Delayed::Job.where(strand: 'strand1').count).to eq 5
    described_class.run
    # The currently running job is kept
    expect(Delayed::Job.count).to eq 1

    activate_target_shard do
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

  it 'should create a blocker singleton if a strandless singleton is currently running' do
    activate_source_shard do
      Kernel.delay(locked_at: DateTime.now, locked_by: 'w1', singleton: 'singleton1').sleep(0.1)
      Kernel.delay(singleton: 'singleton1').sleep(0.1)
    end

    expect(Delayed::Job.count).to eq 2
    described_class.run
    # the original running job
    expect(Delayed::Job.count).to eq 1

    activate_target_shard do
      expect(
        Delayed::Job.where('locked_at IS NOT NULL AND locked_by IS NOT NULL').where(singleton: 'singleton1').count
      ).to eq 1
      expect(
        Delayed::Job.where('locked_at IS NULL AND locked_by IS NULL').where(singleton: 'singleton1').count
      ).to eq 1

      # the blocker job + previously queued job
      expect(Delayed::Job.count).to eq 2
    end
  end

  it 'should handle pre-existing (or migrated earlier in the run) singleton jobs gracefully' do
    activate_source_shard do
      Kernel.delay(singleton: 'singleton1').sleep(0.1)
    end
    activate_target_shard do
      Kernel.delay(singleton: 'singleton1').sleep(0.1)
    end

    expect(Delayed::Job.where(singleton: 'singleton1').count).to eq 1
    activate_target_shard do
      expect(Delayed::Job.where(singleton: 'singleton1').count).to eq 1
    end
    described_class.run
    # The singleton was dropped from this shard
    expect(Delayed::Job.where(singleton: 'singleton1').count).to eq 0

    # There is still one singleton on the new shard
    activate_target_shard do
      expect(Delayed::Job.where(singleton: 'singleton1').count).to eq 1
    end
  end

  context 'before_move_callbacks' do
    it 'Should pass the original job record to a callback' do
      @old_job = nil
      # rubocop:todo Lint/UnusedBlockArgument
      described_class.add_before_move_callback(->(old_job:, new_job:) { @old_job = old_job })
      # rubocop:enable Lint/UnusedBlockArgument
      activate_source_shard do
        Kernel.delay(strand: 'strand', ignore_transaction: true).sleep(0)
      end
      described_class.run
      expect(@old_job.shard).to eq(Switchman::Shard.default)
      described_class.clear_callbacks!
    end

    it 'Should pass the new job record to a callback' do
      @new_job = nil
      # rubocop:todo Lint/UnusedBlockArgument
      described_class.add_before_move_callback(->(old_job:, new_job:) { @new_job = new_job })
      # rubocop:enable Lint/UnusedBlockArgument
      activate_source_shard do
        Kernel.delay(strand: 'strand', ignore_transaction: true).sleep(0)
      end
      described_class.run
      expect(@new_job.shard).to eq(shard1)
      described_class.clear_callbacks!
    end

    it 'Should call before the new job record is saved' do
      @new_job = nil
      # rubocop:todo Lint/UnusedBlockArgument
      described_class.add_before_move_callback(->(old_job:, new_job:) { @new_job = new_job })
      # rubocop:enable Lint/UnusedBlockArgument
      activate_source_shard do
        Kernel.delay(strand: 'strand', ignore_transaction: true).sleep(0)
      end
      described_class.run
      expect(@new_job.new_record?).to be true
    end
  end

  context 'validation_callbacks' do
    it 'Should abort moving if validation fails' do
      # rubocop:todo Lint/UnusedBlockArgument
      described_class.add_validation_callback(->(shard:, target_shard:) { raise 'bad move' })
      # rubocop:enable Lint/UnusedBlockArgument
      activate_source_shard do
        Kernel.delay(strand: 'strand', ignore_transaction: true).sleep(0)
      end
      expect { described_class.migrate_shards({ shard1 => shard1 }) }.to raise_error('bad move')
      described_class.clear_callbacks!
    end

    it 'Should succeed moving if validation succeeds' do
      # rubocop:todo Lint/UnusedBlockArgument
      described_class.add_validation_callback(->(shard:, target_shard:) { 'noop' })
      # rubocop:enable Lint/UnusedBlockArgument
      activate_source_shard do
        Kernel.delay(strand: 'strand', ignore_transaction: true).sleep(0)
      end
      expect { described_class.migrate_shards({ shard1 => shard1 }) }.not_to raise_error
      described_class.clear_callbacks!
    end
  end
end
