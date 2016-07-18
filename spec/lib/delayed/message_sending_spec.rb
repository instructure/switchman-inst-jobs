describe SwitchmanInstJobs::Delayed::MessageSending do
  shared_examples_for 'batch jobs sharding' do
    it 'should keep track of the current shard on child jobs' do
      project.shard.activate do
        ::Delayed::Batch.serial_batch do
          expect(
            'string'.send_later_enqueue_args(:size, no_delay: true)
          ).to be true
          expect(
            'string'.send_later_enqueue_args(
              :gsub, { no_delay: true }, /./, '!'
            )
          ).to be true
        end
      end
      job = ::Delayed::Job.find_available(1).first
      expect(job.current_shard).to eq project.shard
      expect(job.payload_object.jobs.first.current_shard).to eq project.shard
    end
  end

  context 'unsharded project' do
    let(:project) { Project.create! }

    include_examples 'batch jobs sharding'
  end

  context 'sharded project' do
    let(:project) { Project.create_sharded! }

    include_examples 'batch jobs sharding'
  end
end
