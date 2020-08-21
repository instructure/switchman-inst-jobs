describe SwitchmanInstJobs::JobsMigrator do
  let(:shard1) { Switchman::Shard.create }

  before do
    shard1.delayed_jobs_shard_id = shard1.id
    shard1.save!
  end

  it "should move strand'd jobs, but not non-strand'd jobs" do
    # bad other specs for leaving stuff in here
    starting_count = Delayed::Job.count

    Switchman::Shard.activate(primary: shard1, delayed_jobs: Switchman::Shard.default) do
      expect(Switchman::Shard.current(:delayed_jobs)).to eq Switchman::Shard.default
      5.times { Kernel.send_later_enqueue_args(:sleep, { strand: 'strand1' }, 0.1) }
      6.times { Kernel.send_later_enqueue_args(:sleep, { strand: 'strand2' }, 0.2) }
      7.times { Kernel.send_later_enqueue_args(:sleep, {}, 0.3) }
    end
    4.times { Kernel.send_later_enqueue_args(:sleep, {}, 0.4) }

    shard1.activate(:primary, :delayed_jobs) do
      3.times { Kernel.send_later_enqueue_args(:sleep, { strand: 'strand1' }, 0.5) }
      expect(Delayed::Job.count).to eq 3
    end

    # 5 + 6 + 7 + 4
    expect(Delayed::Job.count).to eq starting_count + 22
    described_class.run
    # 7 + 4
    expect(Delayed::Job.count).to eq starting_count + 11

    shard1.activate(:delayed_jobs) do
      # 5 + 6 + 3
      expect(Delayed::Job.count).to eq 14
      # 0.1 jobs come before 0.5 jobs
      strand = Delayed::Job.where(strand: 'strand1')
      first_job = strand.order(:id).first
      expect(first_job.payload_object.args).to eq [0.1]
      # when the current running job on other shard finishes it will set next_in_strand
      expect(first_job.next_in_strand).to be_falsy
      expect(strand.where(next_in_strand: true).count).to eq 1
    end
  end

  it 'should move all jobs if requested to drain' do
    # bad other specs for leaving stuff in here
    starting_count = Delayed::Job.count

    Switchman::Shard.activate(primary: shard1, delayed_jobs: Switchman::Shard.default) do
      expect(Switchman::Shard.current(:delayed_jobs)).to eq Switchman::Shard.default
      7.times { Kernel.send_later_enqueue_args(:sleep, {}, 0.3) }
    end
    4.times { Kernel.send_later_enqueue_args(:sleep, {}, 0.4) }

    # 7 + 4
    expect(Delayed::Job.count).to eq starting_count + 11
    described_class.run(drain: true)
    expect(Delayed::Job.count).to eq starting_count + 4

    shard1.activate(:delayed_jobs) do
      expect(Delayed::Job.count).to eq 7
    end
  end

  context 'negative id jobs' do
    def create_job_with_id(id)
      Switchman::Shard.activate(primary: shard1, delayed_jobs: Switchman::Shard.default) do
        j = Kernel.send_later_enqueue_args(:sleep, strand: 'strand', no_delay: true)
        Delayed::Job.where(id: j).update_all(id: id)
      end
    end

    it 'pukes if there are negative jobs but no room to move them' do
      expect(Delayed::Job.count).to eq 0
      create_job_with_id(-1)
      create_job_with_id(1)
      expect { described_class.run }.to raise_error(/negative IDs/)
    end

    it 'automatically moves a job if there is room' do
      expect(Delayed::Job.count).to eq 0
      create_job_with_id(-1)
      create_job_with_id(2)
      described_class.run
    end

    it "moves jobs by compacting if there's room" do
      expect(Delayed::Job.count).to eq 0
      create_job_with_id(-10)
      create_job_with_id(-7)
      create_job_with_id(20)
      described_class.run
    end

    it "pukes if it can't move a job to a higher id" do
      expect(Delayed::Job.count).to eq 0
      create_job_with_id(-1)
      create_job_with_id(2)
      Delayed::Job.where(id: -1).update_all(locked_by: 'me', locked_at: Time.now.utc)
      expect { described_class.run }.to raise_error(/negative IDs/)
    end
  end

  context 'before_move_callbacks' do
    it 'Should pass the original job record to a callback' do
      @old_job = nil
      # rubocop:todo Lint/UnusedBlockArgument
      described_class.add_before_move_callback(->(old_job:, new_job:) { @old_job = old_job })
      # rubocop:enable Lint/UnusedBlockArgument
      Switchman::Shard.activate(primary: shard1, delayed_jobs: Switchman::Shard.default) do
        Kernel.send_later_enqueue_args(:sleep, strand: 'strand', no_delay: true)
      end
      described_class.run
      expect(@old_job.shard).to eq(Switchman::Shard.default)
    end

    it 'Should pass the new job record to a callback' do
      @new_job = nil
      # rubocop:todo Lint/UnusedBlockArgument
      described_class.add_before_move_callback(->(old_job:, new_job:) { @new_job = new_job })
      # rubocop:enable Lint/UnusedBlockArgument
      Switchman::Shard.activate(primary: shard1, delayed_jobs: Switchman::Shard.default) do
        Kernel.send_later_enqueue_args(:sleep, strand: 'strand', no_delay: true)
      end
      described_class.run
      expect(@new_job.shard).to eq(shard1)
    end

    it 'Should call before the new job record is saved' do
      @new_job = nil
      # rubocop:todo Lint/UnusedBlockArgument
      described_class.add_before_move_callback(->(old_job:, new_job:) { @new_job = new_job })
      # rubocop:enable Lint/UnusedBlockArgument
      Switchman::Shard.activate(primary: shard1, delayed_jobs: Switchman::Shard.default) do
        Kernel.send_later_enqueue_args(:sleep, strand: 'strand', no_delay: true)
      end
      described_class.run
      expect(@new_job.new_record?).to be false
    end
  end
end
