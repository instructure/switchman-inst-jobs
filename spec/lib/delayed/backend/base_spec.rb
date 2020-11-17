describe SwitchmanInstJobs::Delayed::Backend::Base do
  let(:shard) { Switchman::Shard.create }
  let(:project) { Project.create_sharded! }
  let(:harness_class) do
    Class.new(ApplicationRecord) do
      prepend SwitchmanInstJobs::Delayed::Backend::Base

      attr_accessor :shard_id

      define_singleton_method(:columns) { [] }
      define_singleton_method(:columns_hash) { {} }
      define_singleton_method(:load_schema!) do
        # Do nothing for specs
      end

      define_method(:invoke_job) do
        # Do nothing for specs
      end
      define_method(:deserialize) { |source| "Deserialized #{source}" }
    end
  end
  let(:harness) { harness_class.new }

  describe '#enqueue' do
    it 'should enqueue on the correct shard' do
      expect(::ActiveRecord::Migration).to receive(:open_migrations).and_return(1)
      expect(::Switchman::Shard.current.delayed_jobs_shard).
        to receive(:activate).at_least(:once).and_return('success')

      expect(harness.class.enqueue(:fake_args)).to eq('success')
    end

    it 'should enqueue with next_in_strand=true if the strand is empty and block_stranded is false' do
      ::Switchman::Shard.current.block_stranded = false
      ::Switchman::Shard.current.save!

      Kernel.delay(strand: 'strand78').sleep(0.1)
      expect(Delayed::Job.where(strand: 'strand78').count).to eq 1
      expect(Delayed::Job.where(strand: 'strand78').first.next_in_strand).to eq true
    end

    it 'should enqueue with next_in_strand=false if the strand is empty and block_stranded is true' do
      ::Switchman::Shard.current.block_stranded = true
      ::Switchman::Shard.current.save!

      Kernel.delay(strand: 'strand79').sleep(0.1)
      expect(Delayed::Job.where(strand: 'strand79').count).to eq 1
      expect(Delayed::Job.where(strand: 'strand79').first.next_in_strand).to eq false

      ::Switchman::Shard.current.block_stranded = false
      ::Switchman::Shard.current.save!
    end
  end

  describe '#current_shard' do
    it 'can load the current shard based on stored id' do
      expect(::Switchman::Shard).to receive(:lookup).once.with(4).and_return(4)
      harness.shard_id = 4
      expect(harness.current_shard).to eq(4)
    end
  end

  describe '#current_shard=' do
    it 'assigns the id of provided shard' do
      harness.current_shard = shard
      expect(harness.shard_id).to eq(shard.id)
    end

    it 'nulls out the shard id for the default shard' do
      harness.shard_id = shard.id
      harness.current_shard = ::Switchman::DefaultShard.instance
      expect(harness.shard_id).to be_nil
    end

    it 'does not lock the job if jobs are not held on the current shard' do
      shard.unhold_jobs!
      job = nil
      shard.activate do
        job = 'string'.delay(ignore_transaction: true).size
      end
      expect(job.locked_by).to be_nil
      expect(job.locked_at).to be_nil
    end

    it 'locks the job if jobs are held on the current shard' do
      shard.hold_jobs!
      job = nil
      shard.activate do
        job = 'string'.delay(ignore_transaction: true).size
      end
      expect(job.locked_by).to_not be_nil
      expect(job.locked_at).to_not be_nil
      shard.unhold_jobs!
    end
  end

  describe '#invoke_job' do
    it 'should activate the associated job shard' do
      payload_object = double
      expect(payload_object).to receive(:perform).once
      expect_any_instance_of(::Delayed::Backend::Base).
        to receive(:payload_object) { payload_object }
      job = nil

      shard.activate do
        job = 'string'.delay(ignore_transaction: true).size
      end
      expect(job).not_to be_nil
      expect(job.current_shard).to eq shard

      job.invoke_job
    end
  end

  describe '#deserialize' do
    it 'wraps the aliased version of the deserialize method' do
      harness.shard_id = shard.id
      output = harness.deserialize('DelayedJobSpec')
      expect(output).to eq('Deserialized DelayedJobSpec')
    end

    it 'raises an error for invalid shards' do
      unused_id = ::Switchman::Shard.maximum(:id) + 1
      harness.shard_id = unused_id
      expect { harness.deserialize('') }.
        to raise_error("Shard not found: #{unused_id}")
    end

    it 'standardizes db failures' do
      # if a shard no longer exists, trying to use it for this job will bomb
      expect_any_instance_of(::Delayed::Backend::Base).
        to receive(:deserialize).once.and_raise(PG::ConnectionBad)

      payload = ::Delayed::PerformableMethod.new(project, :id)
      job = ::Delayed::Job.create! payload_object: payload
      job.current_shard = project.shard
      job.save!

      destroyed_shard_id = job.current_shard.id
      project.shard.destroy

      reloaded_job = ::Delayed::Job.find_available(1).first

      expect { reloaded_job.invoke_job }.
        to raise_error("Shard not found: #{destroyed_shard_id}")
    end

    it 'passes exception through if the shard still exists' do
      expect_any_instance_of(::Delayed::Backend::Base).
        to receive(:deserialize).once.and_raise(PG::ConnectionBad)

      payload = ::Delayed::PerformableMethod.new(project, :id)
      job = ::Delayed::Job.create! payload_object: payload
      job.current_shard = project.shard
      job.save!

      reloaded_job = ::Delayed::Job.find_available(1).first

      expect { reloaded_job.invoke_job }.
        to raise_error(PG::ConnectionBad)
    end
  end
end
