describe SwitchmanInstJobs::Delayed::MessageSending do
  shared_examples_for 'batch jobs sharding' do
    it 'should keep track of the current shard on child jobs' do
      project.shard.activate do
        ::Delayed::Batch.serial_batch do
          expect(
            'string'.delay(ignore_transaction: true).size
          ).to be true
          expect(
            'string'.delay(ignore_transaction: true).gsub(/./, '!')
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
    include Switchman::RSpecHelper

    let(:project) { @shard1.activate { Project.create! } }

    include_examples 'batch jobs sharding'
  end
end
