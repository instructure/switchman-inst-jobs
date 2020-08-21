# Just disabling all the rubocop metrics for this file for now,
# as it is a direct port-in of existing code

# rubocop:disable Metrics/BlockLength, Metrics/MethodLength, Metrics/AbcSize, Metrics/ClassLength
require 'set'
require 'parallel'

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

      def migrate_shards(shard_map)
        source_shards = Set[]
        shard_map.each do |(shard, target_shard)|
          shard = ::Switchman::Shard.find(shard) unless shard.is_a?(::Switchman::Shard)
          source_shards << shard.delayed_jobs_shard.id
          # If target_shard is an int, it won't have an id, but we can just use it as is
          shard.update(delayed_jobs_shard_id: target_shard.try(:id) || target_shard, block_stranded: true)
        end

        # Wait a little over the 60 second in-process shard cache clearing
        # threshold to ensure that all new stranded jobs are now being
        # enqueued with next_in_strand: false
        Rails.logger.debug("Waiting for caches to clear (#{source_shard.id} -> #{target_shard.id})")
        sleep(65) unless @skip_cache_wait

        # TODO: 4 has been picked completely out of a hat.  We should make it configurable or something
        Parallel.each(source_shards, in_processes: 4) do |s|
          # Ensure the child processes don't share connections with the parent
          Delayed::Pool.on_fork.call
          ActiveRecord::Base.clear_all_connections!
          s.activate(:delayed_jobs) { run }
        end
      end

      # This method expects that all relevant shards already have block_stranded: true
      # but otherwise jobs can be running normally
      def run
        # Ensure this is never run with a dirty in-memory shard cache
        ::Switchman::Shard.clear_cache
        migrate_strands
        migrate_everything
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
        shard_map = build_shard_map(strand_scope, source_shard)
        shard_map.each do |(target_shard, source_shard_ids)|
          shard_scope = strand_scope.where(shard_id: source_shard_ids)

          # 1) is taken care of because it should not show up here in strands
          strands = shard_scope.distinct.order(:strand).pluck(:strand)

          target_shard.activate(:delayed_jobs) do
            strands.each do |strand|
              transaction_on([source_shard, target_shard]) do
                this_strand_scope = shard_scope.where(strand: strand)
                # we want to copy all the jobs except the one that is still running.
                jobs_scope = this_strand_scope.where(locked_by: nil)

                # 2) and part of 3) are taken care of here by creating a blocker
                # job with next_in_strand = false. as soon as the current
                # running job is finished it should set next_in_strand
                # We lock it to ensure that the jobs worker can't delete it until we are done moving the strand
                # Since we only unlock it on the new jobs queue *after* deleting from the original
                # the lock ensures the blocker always gets unlocked
                first = this_strand_scope.where('locked_by IS NOT NULL').next_in_strand_order.lock.first
                if first
                  first_job = ::Delayed::Job.create!(strand: strand, next_in_strand: false)
                  first_job.payload_object = ::Delayed::PerformableMethod.new(Kernel, :sleep, [0])
                  first_job.queue = first.queue
                  first_job.tag = 'Kernel.sleep'
                  first_job.source = 'JobsMigrator::StrandBlocker'
                  first_job.max_attempts = 1
                  # If we ever have jobs left over from 9999 jobs moves of a single shard,
                  # something has gone terribly wrong
                  first_job.strand_order_override = -9999
                  first_job.save!
                  # the rest of 3) is taken care of here
                  # make sure that all the jobs moved over are NOT next in strand
                  ::Delayed::Job.where(next_in_strand: true, strand: strand, locked_by: nil)
                    .update_all(next_in_strand: false)
                end

                # 4) is taken care of here, by leaveing next_in_strand alone and
                # it should execute on the new shard
                batch_move_jobs(
                  target_shard: target_shard,
                  source_shard: source_shard,
                  scope: jobs_scope
                ) do |job, new_job|
                  # This ensures jobs enqueued on the old jobs shard run before jobs on the new jobs queue
                  new_job.strand_order_override = job.strand_order_override - 1
                end
              end
            end

            ::Switchman::Shard.find(source_shard_ids).each do |shard|
              shard.update(block_stranded: false)
            end
            # Wait a little over the 60 second in-process shard cache clearing
            # threshold to ensure that all new stranded jobs are now being
            # enqueued with next_in_strand: false
            Rails.logger.debug("Waiting for caches to clear (#{source_shard.id} -> #{target_shard.id})")
            # for spec usage only
            sleep(65) unless @skip_cache_wait
            # At this time, let's unblock all the strands on the target shard that aren't being held by a blocker
            # but actually could have run and we just didn't know it because we didn't know if they had jobs
            # on the source shard
            # rubocop:disable Layout/LineLength
            strands_to_unblock = shard_scope.where.not(source: 'JobsMigrator::StrandBlocker')
              .distinct
              .where("NOT EXISTS (SELECT 1 FROM #{::Delayed::Job.quoted_table_name} dj2 WHERE delayed_jobs.strand=dj2.strand AND next_in_strand)")
              .pluck(:strand)
            # rubocop:enable Layout/LineLength
            strands_to_unblock.each do |strand|
              Delayed::Job.where(strand: strand).next_in_strand_order.first.update_attribute(:next_in_strand, true)
            end
          end
        end
      end

      def migrate_everything
        source_shard = ::Switchman::Shard.current(:delayed_jobs)
        scope = ::Delayed::Job.shard(source_shard).where('strand IS NULL')

        shard_map = build_shard_map(scope, source_shard)
        shard_map.each do |(target_shard, source_shard_ids)|
          batch_move_jobs(
            target_shard: target_shard,
            source_shard: source_shard,
            scope: scope.where(shard_id: source_shard_ids).where(locked_by: nil)
          )
        end
      end

      private

      def build_shard_map(scope, source_shard)
        shard_ids = scope.distinct.pluck(:shard_id)

        shard_map = {}
        ::Switchman::Shard.find(shard_ids).each do |shard|
          next if shard.delayed_jobs_shard == source_shard

          shard_map[shard.delayed_jobs_shard] ||= []
          shard_map[shard.delayed_jobs_shard] << shard.id
        end

        shard_map
      end

      def batch_move_jobs(target_shard:, source_shard:, scope:)
        while scope.exists?
          # Adapted from get_and_lock_next_available in delayed/backend/active_record.rb
          target_jobs = scope.limit(1000).lock('FOR UPDATE SKIP LOCKED')

          query = "WITH limited_jobs AS (#{target_jobs.to_sql}) " \
                  "UPDATE #{::Delayed::Job.quoted_table_name} " \
                  "SET locked_by = #{::Delayed::Job.connection.quote(::Delayed::Backend::Base::ON_HOLD_LOCKED_BY)}, " \
                  "locked_at = #{::Delayed::Job.connection.quote(::Delayed::Job.db_time_now)} "\
                  "FROM limited_jobs WHERE limited_jobs.id=#{::Delayed::Job.quoted_table_name}.id " \
                  "RETURNING #{::Delayed::Job.quoted_table_name}.*"

          jobs = source_shard.activate(:delayed_jobs) { ::Delayed::Job.find_by_sql(query) }
          new_jobs = jobs.map do |job|
            new_job = job.dup
            new_job.shard = target_shard
            new_job.created_at = job.created_at
            new_job.updated_at = job.updated_at
            new_job.locked_at = nil
            new_job.locked_by = nil
            yield(job, new_job) if block_given?
            @before_move_callbacks&.each do |proc|
              proc.call(
                old_job: job,
                new_job: new_job
              )
            end
            new_job
          end
          transaction_on([source_shard, target_shard]) do
            target_shard.activate(:delayed_jobs) do
              bulk_insert_jobs(new_jobs)
            end
            source_shard.activate(:delayed_jobs) do
              ::Delayed::Job.delete(jobs)
            end
          end
        end
      end

      # This is adapted from the postgreql adapter in canvas-lms
      # Once we stop supporting rails 5.2 we can just use insert_all from activerecord
      def bulk_insert_jobs(objects)
        records = objects.map do |object|
          object.attributes.map do |(name, value)|
            next if name == ::Delayed::Job.primary_key

            if (type = ::Delayed::Job.attribute_types[name]).is_a?(::ActiveRecord::Type::Serialized)
              value = type.serialize(value)
            end
            [name, value]
          end.compact.to_h
        end
        return if records.length.zero?

        keys = records.first.keys

        connection = ::Delayed::Job.connection
        quoted_keys = keys.map { |k| connection.quote_column_name(k) }.join(', ')

        connection.execute "COPY #{::Delayed::Job.quoted_table_name} (#{quoted_keys}) FROM STDIN"
        records.map do |record|
          connection.raw_connection.put_copy_data(keys.map { |k| quote_text(record[k]) }.join("\t") + "\n")
        end
        connection.clear_query_cache
        connection.raw_connection.put_copy_end
        result = connection.raw_connection.get_result
        begin
          result.check
        rescue StandardError => e
          raise connection.send(:translate_exception, e, 'COPY FROM STDIN')
        end
        result.cmd_tuples
      end

      # See above comment...
      def quote_text(value)
        if value.nil?
          '\\N'
        elsif value.is_a?(::ActiveRecord::ConnectionAdapters::PostgreSQL::OID::Array::Data)
          quote_text(encode_array(value))
        else
          hash = { "\n" => '\\n', "\r" => '\\r', "\t" => '\\t', '\\' => '\\\\' }
          value.to_s.gsub(/[\n\r\t\\]/) { |c| hash[c] }
        end
      end
    end
  end
end

# rubocop:enable Metrics/BlockLength, Metrics/MethodLength, Metrics/AbcSize, Metrics/ClassLength
