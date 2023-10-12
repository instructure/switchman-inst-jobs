# frozen_string_literal: true

module SwitchmanInstJobs
  module Delayed
    module Pool
      def initialize(*)
        super

        raise "Cannot run jobs cross-region" unless shards.all?(&:in_current_region?)
      end

      def unlock_orphaned_jobs(worker = nil, pid = nil)
        if worker
          # this is just a failsafe; it shouldn't be possible
          return unless worker.shard.in_current_region?

          shards = [worker.shard]
        else
          # Since we're not unlocking for a specific worker, look through
          # the config for all shards this pool has workers for, and unlock
          # on each shard found.
          #
          # If this host used to have workers for shard X, and then it died
          # ungracefully at the same time that all workers for shard X were
          # removed, we won't properly unlock those jobs here. That's an
          # acceptable edge case though.
          #
          # We purposely don't .compact to remove nils here, since if any
          # workers are on the default jobs shard we want to unlock against
          # that shard too.

          shards = self.shards.select(&:in_current_region?)
        end
        ::Switchman::Shard.with_each_shard(shards, [::Delayed::Backend::ActiveRecord::AbstractJob]) do
          super
        end
      end

      def shards
        shard_ids = @config[:workers].pluck(:shard).uniq
        shard_ids.map { |shard_id| ::Delayed::Worker.shard(shard_id) }
      end
    end
  end
end
