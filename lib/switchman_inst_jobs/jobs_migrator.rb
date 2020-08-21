# Just disabling all the rubocop metrics for this file for now,
# as it is a direct port-in of existing code

# rubocop:disable Metrics/BlockLength, Metrics/MethodLength, Metrics/AbcSize, Metrics/ClassLength, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity

module SwitchmanInstJobs
  class JobsMigrator
    class << self
      def add_before_move_callback(proc)
        @before_move_callbacks ||= []
        @before_move_callbacks << proc
      end

      def transaction_on(shards, &block)
        return yield if shards.empty?

        shard = shards.pop
        current_shard = ::Switchman::Shard.current(:delayed_jobs)
        shard.activate(:delayed_jobs) do
          ::Delayed::Job.transaction do
            current_shard.activate(:delayed_jobs) do
              transaction_on(shards, &block)
            end
          end
        end
      end

      def run(drain: false)
        migrate_strands
        migrate_everything if drain
      end

      def migrate_strands
        # there are 4 scenarios to deal with here
        # 1) no running job, no jobs moved: do nothing
        # 2) running job, no jobs moved; create blocker with next_in_strand=false
        #    to prevent new jobs from immediately executing
        # 3) running job, jobs moved; set next_in_strand=false on the first of
        #    those (= do nothing since it should already be false)
        # 4) no running job, jobs moved: set next_in_strand=true on the first of
        #    those (= do nothing since it should already be true)

        source_shard = ::Switchman::Shard.current(:delayed_jobs)
        strand_scope = ::Delayed::Job.shard(source_shard).where('strand IS NOT NULL')
        shard_ids = strand_scope.distinct.pluck(:shard_id)

        shard_map = {}
        ::Switchman::Shard.find(shard_ids).each do |shard|
          next if shard.delayed_jobs_shard == source_shard

          shard_map[shard.delayed_jobs_shard] ||= []
          shard_map[shard.delayed_jobs_shard] << shard.id
        end

        shard_map.each do |(target_shard, source_shard_ids)|
          shard_scope = strand_scope.where(shard_id: source_shard_ids)

          # negative IDs from a previous jobs migration are bad news!
          unless (jobs_to_move = shard_scope.where('id<0').order(:id).pluck(:id)).empty?
            # can we just shift them?
            available_space = ::Delayed::Job.where('id>0').minimum(:id)
            # available_space is highly unlikely to be NULL. don't bother handling that case gracefully
            if available_space.nil? || jobs_to_move.length >= available_space
              raise 'You have jobs with negative IDs from a previous jobs migration; please wait for them to clear.'
            end

            ::Delayed::Job.transaction do
              total = 0
              jobs_to_move.each_slice(1000) do |slice|
                transpositions = 'id=CASE id '
                slice.each_with_index do |j_id, i|
                  transpositions << "WHEN #{j_id} THEN #{available_space - jobs_to_move.length + total + i} "
                end
                transpositions << 'END'
                total += slice.length

                next if shard_scope.where(id: slice)
                  .where("id<0 AND (locked_by IS NULL OR locked_by LIKE 'prefetch%')")
                  .update_all(transpositions) == slice.length

                raise 'You have jobs with negative IDs from a previous jobs migration; please wait for them to clear.'
              end
            end
          end

          # 1) is taken care of because it should not show up here in strands
          strands = shard_scope.distinct.order(:strand).pluck(:strand)

          target_shard.activate(:delayed_jobs) do
            strands.each do |strand|
              transaction_on([source_shard, target_shard]) do
                this_strand_scope = shard_scope.where(strand: strand)
                # we want to copy all the jobs except the one that is still running.
                jobs_scope = this_strand_scope.where(locked_by: nil)
                jobs = jobs_scope.order(:id).to_a
                max_id = this_strand_scope.last&.local_id
                min_id_on_new_shard = ::Delayed::Job.minimum(:id) || 1
                id_delta = min_id_on_new_shard - max_id - 1 if max_id
                id_delta ||= 0

                # 2) and part of 3) are taken care of here by creating a blocker
                # job with next_in_strand = false. as soon as the current
                # running job is finished it should set next_in_strand
                strand_is_in_future = false
                if (first = this_strand_scope.where('locked_by IS NOT NULL').first)
                  strand_is_in_future = true if first.run_at > Time.now.utc + 10.minutes
                  unless strand_is_in_future
                    first_job = ::Delayed::Job.create!(strand: strand, next_in_strand: false)
                    first_job.id = id_delta
                    first_job.payload_object = ::Delayed::PerformableMethod.new(Kernel, :sleep, [0])
                    first_job.queue = first.queue
                    first_job.tag = 'Kernel.sleep'
                    first_job.source = 'JobsMigrator::StrandBlocker'
                    first_job.max_attempts = 1
                    first_job.save!
                    # the rest of 3) is taken care of here
                    # make sure that all the jobs moved over are NOT next in strand
                    ::Delayed::Job.where(next_in_strand: true, strand: strand, locked_by: nil)
                      .update_all(next_in_strand: false)
                  end
                end

                # 4) is taken care of here, by leaveing next_in_strand alone and
                # it should execute on the new shard
                jobs.each do |job|
                  new_job = job.dup
                  new_job.shard = target_shard
                  new_job.id = job.local_id + id_delta unless strand_is_in_future
                  @before_move_callbacks&.each do |proc|
                    proc.call(
                      old_job: job,
                      new_job: new_job
                    )
                  end
                  new_job.save!
                end

                # delete all jobs that are not currently running.
                source_shard.activate(:delayed_jobs) { jobs_scope.delete_all }
              end
            end
          end
        end
      end

      def migrate_everything
        source_shard = ::Switchman::Shard.current(:delayed_jobs)
        scope = ::Delayed::Job.shard(source_shard).where('strand IS NULL')
        shard_ids = scope.distinct.pluck(:shard_id)

        shard_map = {}
        ::Switchman::Shard.find(shard_ids).each do |shard|
          next if shard.delayed_jobs_shard == source_shard

          shard_map[shard.delayed_jobs_shard] ||= []
          shard_map[shard.delayed_jobs_shard] << shard.id
        end

        shard_map.each do |(target_shard, source_shard_ids)|
          scope.where(shard_id: source_shard_ids).find_each do |job|
            new_job = job.dup
            new_job.shard = target_shard
            @before_move_callbacks&.each do |proc|
              proc.call(
                old_job: job,
                new_job: new_job
              )
            end
            transaction_on([source_shard, target_shard]) do
              new_job.save!
              job.destroy
            end
          end
        end
      end
    end
  end
end

# rubocop:enable Metrics/BlockLength, Metrics/MethodLength, Metrics/AbcSize, Metrics/ClassLength, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
