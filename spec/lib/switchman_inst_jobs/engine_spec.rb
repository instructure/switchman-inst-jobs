# frozen_string_literal: true

describe SwitchmanInstJobs::Engine do
  context "with multiple job shards" do
    include Switchman::RSpecHelper

    let(:shard1) { @shard1 }
    let(:shard2) { @shard2 }
    let(:work_queue) { Delayed::WorkQueue::InProcess.new }
    let(:worker_config1) { { shard: shard1.id, queue: "test1" } }
    let(:worker_config2) { { shard: shard2.id, queue: "test2" } }
    let(:args1) { ["worker_name1", worker_config1] }
    let(:args2) { ["worker_name2", worker_config2] }

    it "activates the configured job shard1 to pop jobs" do
      expect(Delayed::Job).to receive(:get_and_lock_next_available)
        .once.with("worker_name1", "test1", nil, nil) do
        expect(Switchman::Shard.current(Delayed::Backend::ActiveRecord::AbstractJob)).to eq shard1
        nil
      end
      work_queue.get_and_lock_next_available(*args1)
    end

    it "activates the configured job shard2 to pop jobs" do
      expect(Delayed::Job).to receive(:get_and_lock_next_available)
        .once.with("worker_name2", "test2", nil, nil) do
        expect(Switchman::Shard.current(Delayed::Backend::ActiveRecord::AbstractJob)).to eq shard2
        nil
      end
      work_queue.get_and_lock_next_available(*args2)
    end

    context "non_transactional", use_transactional_fixtures: false do
      after do
        # we're disabling automatic transaction wrapping, so ensure we clean up properly
        shard1.activate(Delayed::Backend::ActiveRecord::AbstractJob) do
          Delayed::Job.delete_all
        end

        shard2.activate(Delayed::Backend::ActiveRecord::AbstractJob) do
          Delayed::Job.delete_all
        end

        Switchman::Shard.current.delayed_jobs_shard_id = nil
        Switchman::Shard.current.save!
      end

      it "deletes the strand blocker for stranded jobs" do
        shard1.activate(Delayed::Backend::ActiveRecord::AbstractJob) do
          expect(Switchman::Shard.current).to eq Switchman::Shard.default
          expect(Switchman::Shard.current(Delayed::Backend::ActiveRecord::AbstractJob)).to eq shard1
          Kernel.delay(strand: "strand1", queue: "test1").sleep(0.1)
        end

        shard2.activate(Delayed::Backend::ActiveRecord::AbstractJob) do
          expect(Delayed::Job.count).to eq 0
          expect(Switchman::Shard.current).to eq Switchman::Shard.default
          expect(Switchman::Shard.current(Delayed::Backend::ActiveRecord::AbstractJob)).to eq shard2

          Kernel.delay(strand: "strand1",
                       queue: "test1",
                       locked_by: "strand blocker",
                       locked_at: Time.now.utc,
                       source: "JobsMigrator::StrandBlocker").sleep(0.1)
          Delayed::Job.first.update!(next_in_strand: false)

          Kernel.delay(strand: "strand1", queue: "test1").sleep(0.1)
          Delayed::Job.last.update!(next_in_strand: false)
        end

        Switchman::Shard.current.delayed_jobs_shard_id = shard2.id
        Switchman::Shard.current.save!

        shard2.activate(Delayed::Backend::ActiveRecord::AbstractJob) do
          expect(Delayed::Job.first.source).to eq "JobsMigrator::StrandBlocker"
          expect(Delayed::Job.first.next_in_strand).to be false
        end

        Delayed::Worker.new(queue: "test1", worker_max_job_count: 1, shard: shard1.id).run

        shard2.activate(Delayed::Backend::ActiveRecord::AbstractJob) do
          expect(Delayed::Job.first.source).not_to eq "JobsMigrator::StrandBlocker"
          expect(Delayed::Job.first.next_in_strand).to be true
        end
      end

      it "deletes the strand blocker for strandless singleton jobs" do
        shard1.activate(Delayed::Backend::ActiveRecord::AbstractJob) do
          expect(Switchman::Shard.current).to eq Switchman::Shard.default
          expect(Switchman::Shard.current(Delayed::Backend::ActiveRecord::AbstractJob)).to eq shard1
          Kernel.delay(singleton: "singleton1", queue: "test1").sleep(0.1)
        end

        shard2.activate(Delayed::Backend::ActiveRecord::AbstractJob) do
          expect(Delayed::Job.count).to eq 0
          expect(Switchman::Shard.current).to eq Switchman::Shard.default
          expect(Switchman::Shard.current(Delayed::Backend::ActiveRecord::AbstractJob)).to eq shard2

          Kernel.delay(singleton: "singleton1",
                       queue: "test1",
                       locked_by: "singleton blocker",
                       locked_at: Time.now.utc,
                       source: "JobsMigrator::StrandBlocker").sleep(0.1)
          Delayed::Job.first.update!(next_in_strand: false)

          Kernel.delay(singleton: "singleton1", queue: "test1").sleep(0.1)
          Delayed::Job.last.update!(next_in_strand: false)
        end

        Switchman::Shard.current.delayed_jobs_shard_id = shard2.id
        Switchman::Shard.current.save!

        shard2.activate(Delayed::Backend::ActiveRecord::AbstractJob) do
          expect(Delayed::Job.first.source).to eq "JobsMigrator::StrandBlocker"
          expect(Delayed::Job.first.next_in_strand).to be false
        end

        Delayed::Worker.new(queue: "test1", worker_max_job_count: 1, shard: shard1.id).run

        shard2.activate(Delayed::Backend::ActiveRecord::AbstractJob) do
          expect(Delayed::Job.first.source).not_to eq "JobsMigrator::StrandBlocker"
          expect(Delayed::Job.first.next_in_strand).to be true
        end
      end

      it "unblocks stranded jobs on a new shard" do
        Switchman::Shard.current.delayed_jobs_shard_id = shard1.id
        Switchman::Shard.current.save!

        shard1.activate(Delayed::Backend::ActiveRecord::AbstractJob) do
          expect(Switchman::Shard.current).to eq Switchman::Shard.default
          expect(Switchman::Shard.current(Delayed::Backend::ActiveRecord::AbstractJob)).to eq shard1
          Kernel.delay(strand: "strand1", queue: "test1").sleep(0.1)
        end

        shard2.activate(Delayed::Backend::ActiveRecord::AbstractJob) do
          expect(Delayed::Job.count).to eq 0
          expect(Switchman::Shard.current).to eq Switchman::Shard.default
          expect(Switchman::Shard.current(Delayed::Backend::ActiveRecord::AbstractJob)).to eq shard2

          Kernel.delay(strand: "strand1", queue: "test1", next_in_strand: "f").sleep(0.1)
        end

        Switchman::Shard.current.delayed_jobs_shard_id = shard2.id
        Switchman::Shard.current.save!

        shard2.activate(Delayed::Backend::ActiveRecord::AbstractJob) do
          expect(Delayed::Job.first.next_in_strand).to be false
        end

        Delayed::Worker.new(queue: "test1", worker_max_job_count: 1, shard: shard1.id).run

        shard2.activate(Delayed::Backend::ActiveRecord::AbstractJob) do
          expect(Delayed::Job.first.next_in_strand).to be true
        end
      end

      it "unblocks strandless singleton jobs on a new shard" do
        Switchman::Shard.current.delayed_jobs_shard_id = shard1.id
        Switchman::Shard.current.save!

        shard1.activate(Delayed::Backend::ActiveRecord::AbstractJob) do
          expect(Switchman::Shard.current).to eq Switchman::Shard.default
          expect(Switchman::Shard.current(Delayed::Backend::ActiveRecord::AbstractJob)).to eq shard1
          Kernel.delay(singleton: "singleton1", queue: "test1").sleep(0.1)
        end

        shard2.activate(Delayed::Backend::ActiveRecord::AbstractJob) do
          expect(Delayed::Job.count).to eq 0
          expect(Switchman::Shard.current).to eq Switchman::Shard.default
          expect(Switchman::Shard.current(Delayed::Backend::ActiveRecord::AbstractJob)).to eq shard2

          Kernel.delay(singleton: "singleton1", queue: "test1").sleep(0.1)
          Delayed::Job.first.update!(next_in_strand: false)
        end

        Switchman::Shard.current.delayed_jobs_shard_id = shard2.id
        Switchman::Shard.current.save!

        shard2.activate(Delayed::Backend::ActiveRecord::AbstractJob) do
          expect(Delayed::Job.first.next_in_strand).to be false
        end

        Delayed::Worker.new(queue: "test1", worker_max_job_count: 1, shard: shard1.id).run

        shard2.activate(Delayed::Backend::ActiveRecord::AbstractJob) do
          expect(Delayed::Job.first.next_in_strand).to be true
        end
      end
    end
  end
end
