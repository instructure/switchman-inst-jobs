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
        current_shard = ::Switchman::Shard.current(::Delayed::Backend::ActiveRecord::AbstractJob)
        shard.activate(::Delayed::Backend::ActiveRecord::AbstractJob) do
          ::Delayed::Job.transaction do
            current_shard.activate(::Delayed::Backend::ActiveRecord::AbstractJob) do
              transaction_on(shards, &block)
            end
          end
        end
      end

      def migrate_shards(shard_map)
        source_shards = Set[]
        target_shards = Hash.new([])
        shard_map.each do |(shard, target_shard)|
          shard = ::Switchman::Shard.find(shard) unless shard.is_a?(::Switchman::Shard)
          source_shards << shard.delayed_jobs_shard.id
          target_shard = target_shard.try(:id) || target_shard
          target_shards[target_shard] += [shard.id]
        end

        # Do the updates in batches and then just clear redis instead of clearing them one at a time
        target_shards.each do |target_shard, shards|
          updates = { delayed_jobs_shard_id: target_shard, block_stranded: true }
          updates[:updated_at] = Time.zone.now if ::Switchman::Shard.column_names.include?('updated_at')
          ::Switchman::Shard.where(id: shards).update_all(updates)
        end
        clear_shard_cache

        ::Switchman::Shard.clear_cache
        # rubocop:disable Style/CombinableLoops
        # We first migrate strands so that we can stop blocking strands before we migrate unstranded jobs
        source_shards.each do |s|
          ::Switchman::Shard.lookup(s).activate(::Delayed::Backend::ActiveRecord::AbstractJob) { migrate_strands }
        end

        source_shards.each do |s|
          ::Switchman::Shard.lookup(s).activate(::Delayed::Backend::ActiveRecord::AbstractJob) { migrate_everything }
        end
        ensure_unblock_stranded_for(shard_map.map(&:first))
        # rubocop:enable Style/CombinableLoops
      end

      # if :migrate_strands ran on any shards that fell into scenario 1, then
      # block_stranded never got flipped, so do that now.
      def ensure_unblock_stranded_for(shards)
        shards = ::Switchman::Shard.where(id: shards, block_stranded: true).to_a
        return unless shards.any?

        ::Switchman::Shard.where(id: shards).update_all(block_stranded: false)
        clear_shard_cache

        # shards is an array of shard objects that is now stale cause block_stranded has been updated.
        shards.map(&:delayed_jobs_shard).uniq.each do |dj_shard|
          unblock_strands(dj_shard)
        end
      end

      def clear_shard_cache(debug_message = nil)
        ::Switchman.cache.clear
        Rails.logger.debug { "Waiting for caches to clear #{debug_message}" }
        # Wait a little over the 60 second in-process shard cache clearing
        # threshold to ensure that all new stranded jobs are now being
        # enqueued with next_in_strand: false
        # @skip_cache_wait is for spec usage only
        sleep(65) unless @skip_cache_wait
      end

      # This method expects that all relevant shards already have block_stranded: true
      # but otherwise jobs can be running normally
      def run
        # Ensure this is never run with a dirty in-memory shard cache
        ::Switchman::Shard.clear_cache
        migrate_strands
        migrate_everything
      end

      def migrate_strands(batch_size: 1_000)
        source_shard = ::Switchman::Shard.current(::Delayed::Backend::ActiveRecord::AbstractJob)

        # there are 4 scenarios to deal with here
        # 1) no running job, no jobs moved: do nothing
        # 2) running job, no jobs moved; create blocker with next_in_strand=false
        #    to prevent new jobs from immediately executing
        # 3) running job, jobs moved; set next_in_strand=false on the first of
        #    those (= do nothing since it should already be false)
        # 4) no running job, jobs moved: set next_in_strand=true on the first of
        #    those (= do nothing since it should already be true)
        handler = lambda { |scope, column, blocker_job_kwargs = {}|
          shard_map = build_shard_map(scope, source_shard)
          shard_map.each do |(target_shard, source_shard_ids)|
            shard_scope = scope.where(shard_id: source_shard_ids)

            # 1) is taken care of because it should not show up here in strands
            values = shard_scope.distinct.order(column).pluck(column)

            target_shard.activate(::Delayed::Backend::ActiveRecord::AbstractJob) do
              values.each do |value|
                transaction_on([source_shard, target_shard]) do
                  value_scope = shard_scope.where(**{ column => value })
                  # we want to copy all the jobs except the one that is still running.
                  jobs_scope = value_scope.where(locked_by: nil)

                  # 2) and part of 3) are taken care of here by creating a blocker
                  # job with next_in_strand = false. as soon as the current
                  # running job is finished it should set next_in_strand
                  # We lock it to ensure that the jobs worker can't delete it until we are done moving the strand
                  # Since we only unlock it on the new jobs queue *after* deleting from the original
                  # the lock ensures the blocker always gets unlocked
                  first = value_scope.where.not(locked_by: nil).next_in_strand_order.lock.first
                  if first
                    create_blocker_job(queue: first.queue, **{ column => value }, **blocker_job_kwargs)
                    # the rest of 3) is taken care of here
                    # make sure that all the jobs moved over are NOT next in strand
                    ::Delayed::Job.where(next_in_strand: true, locked_by: nil, **{ column => value }).
                      update_all(next_in_strand: false)
                  end

                  # 4) is taken care of here, by leaving next_in_strand alone and
                  # it should execute on the new shard
                  batch_move_jobs(
                    target_shard: target_shard,
                    source_shard: source_shard,
                    scope: jobs_scope,
                    batch_size: batch_size
                  ) do |job, new_job|
                    # This ensures jobs enqueued on the old jobs shard run before jobs on the new jobs queue
                    new_job.strand_order_override = job.strand_order_override - 1
                  end
                end
              end
            end
          end
        }

        strand_scope = ::Delayed::Job.shard(source_shard).where.not(strand: nil)
        singleton_scope = ::Delayed::Job.shard(source_shard).where('strand IS NULL AND singleton IS NOT NULL')
        all_scope = ::Delayed::Job.shard(source_shard).where('strand IS NOT NULL OR singleton IS NOT NULL')

        handler.call(strand_scope, :strand)
        handler.call(singleton_scope, :singleton,
                     { locked_at: DateTime.now, locked_by: ::Delayed::Backend::Base::ON_HOLD_BLOCKER })

        shard_map = build_shard_map(all_scope, source_shard)
        shard_map.each do |(target_shard, source_shard_ids)|
          target_shard.activate(::Delayed::Backend::ActiveRecord::AbstractJob) do
            updated = ::Switchman::Shard.where(id: source_shard_ids, block_stranded: true).
              update_all(block_stranded: false)
            # If this is being manually re-run for some reason to clean something up, don't wait for nothing to happen
            clear_shard_cache("(#{source_shard.id} -> #{target_shard.id})") unless updated.zero?

            ::Switchman::Shard.clear_cache
            # At this time, let's unblock all the strands on the target shard that aren't being held by a blocker
            # but actually could have run and we just didn't know it because we didn't know if they had jobs
            # on the source shard
            unblock_strands(target_shard)
          end
        end
      end

      def unblock_strands(target_shard, batch_size: 10_000)
        block_stranded_ids = ::Switchman::Shard.where(block_stranded: true).pluck(:id)
        query = lambda { |column, scope|
          ::Delayed::Job.
            where(id: ::Delayed::Job.select("DISTINCT ON (#{column}) id").
              where(scope).
              where.not(shard_id: block_stranded_ids).
              where(
                ::Delayed::Job.select(1).from("#{::Delayed::Job.quoted_table_name} dj2").
                where("dj2.next_in_strand = true OR dj2.source = 'JobsMigrator::StrandBlocker'").
                where("dj2.#{column} = delayed_jobs.#{column}").arel.exists.not
              ).
              order(column, :strand_order_override, :id)).limit(batch_size)
        }

        target_shard.activate(::Delayed::Backend::ActiveRecord::AbstractJob) do
          # We only want to unlock stranded jobs where they don't belong to a blocked shard (if they *do* belong)
          # to a blocked shard, they must be part of a concurrent jobs migration from a different source shard to
          # this target shard, so we shouldn't unlock them yet.  We only ever unlock one job here to keep the
          # logic cleaner; if the job is n-stranded, after the first one runs, the trigger will unlock larger
          # batches

          loop do
            break if query.call(:strand, 'strand IS NOT NULL').update_all(next_in_strand: true).zero?
          end

          loop do
            break if query.call(:singleton,
                                'strand IS NULL AND singleton IS NOT NULL').update_all(next_in_strand: true).zero?
          end
        end
      end

      def migrate_everything(batch_size: 1_000)
        source_shard = ::Switchman::Shard.current(::Delayed::Backend::ActiveRecord::AbstractJob)
        scope = ::Delayed::Job.shard(source_shard).where(strand: nil)

        shard_map = build_shard_map(scope, source_shard)
        shard_map.each do |(target_shard, source_shard_ids)|
          batch_move_jobs(
            target_shard: target_shard,
            source_shard: source_shard,
            scope: scope.where(shard_id: source_shard_ids).where(locked_by: nil),
            batch_size: batch_size
          )
        end
      end

      private

      def create_blocker_job(**kwargs)
        first_job = ::Delayed::Job.create!(**kwargs, next_in_strand: false)
        first_job.payload_object = ::Delayed::PerformableMethod.new(Kernel, :sleep, args: [0])
        first_job.tag = 'Kernel.sleep'
        first_job.source = 'JobsMigrator::StrandBlocker'
        first_job.max_attempts = 1
        # If we ever have jobs left over from 9999 jobs moves of a single shard,
        # something has gone terribly wrong
        first_job.strand_order_override = -9999
        first_job.save!
      end

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

      def batch_move_jobs(target_shard:, source_shard:, scope:, batch_size:)
        while scope.exists?
          # Adapted from get_and_lock_next_available in delayed/backend/active_record.rb
          target_jobs = scope.limit(batch_size).lock('FOR UPDATE SKIP LOCKED')

          query = source_shard.activate(::Delayed::Backend::ActiveRecord::AbstractJob) do
            <<~SQL
              WITH limited_jobs AS (#{target_jobs.to_sql})
              UPDATE #{::Delayed::Job.quoted_table_name}
              SET locked_by = #{::Delayed::Job.connection.quote(::Delayed::Backend::Base::ON_HOLD_LOCKED_BY)},
              locked_at = #{::Delayed::Job.connection.quote(::Delayed::Job.db_time_now)}
              FROM limited_jobs WHERE limited_jobs.id=#{::Delayed::Job.quoted_table_name}.id
              RETURNING #{::Delayed::Job.quoted_table_name}.*
            SQL
          end

          jobs = source_shard.activate(::Delayed::Backend::ActiveRecord::AbstractJob) do
            ::Delayed::Job.find_by_sql(query)
          end
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
            target_shard.activate(::Delayed::Backend::ActiveRecord::AbstractJob) do
              bulk_insert_jobs(new_jobs)
            end
            source_shard.activate(::Delayed::Backend::ActiveRecord::AbstractJob) do
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

        connection.execute 'DROP TABLE IF EXISTS delayed_jobs_bulk_copy'
        connection.execute "CREATE TEMPORARY TABLE delayed_jobs_bulk_copy
          (LIKE #{::Delayed::Job.quoted_table_name} INCLUDING DEFAULTS)"
        connection.execute "COPY delayed_jobs_bulk_copy (#{quoted_keys}) FROM STDIN"
        records.map do |record|
          connection.raw_connection.put_copy_data("#{keys.map { |k| quote_text(record[k]) }.join("\t")}\n")
        end
        connection.clear_query_cache
        connection.raw_connection.put_copy_end
        result = connection.raw_connection.get_result
        begin
          result.check
        rescue StandardError => e
          raise connection.send(:translate_exception, e, 'COPY FROM STDIN')
        end
        connection.execute "INSERT INTO #{::Delayed::Job.quoted_table_name} (#{quoted_keys})
          SELECT #{quoted_keys} FROM delayed_jobs_bulk_copy
          ON CONFLICT (singleton) WHERE singleton IS NOT NULL AND locked_by IS NULL DO NOTHING"
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
