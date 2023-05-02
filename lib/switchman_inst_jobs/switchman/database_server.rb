# frozen_string_literal: true

module SwitchmanInstJobs
  module Switchman
    module DatabaseServer
      def delayed_jobs_shard(shard = nil)
        return shard if config[:delayed_jobs_shard] == "self"

        dj_shard =
          config[:delayed_jobs_shard] &&
          ::Switchman::Shard.lookup(config[:delayed_jobs_shard])
        # have to avoid recursion for the default shard asking for the default
        # shard's delayed_jobs_shard
        if shard&.default?
          # first look for any shard that behaves like a jobs shard
          dj_shard ||= ::Switchman::Shard.delayed_jobs_shards.find(&:database_server)
          # we're really truly out of options, use the default shard itself
          dj_shard ||= shard
        end
        dj_shard ||= SwitchmanInstJobs.delayed_jobs_shard_fallback&.call(self, shard)
        dj_shard || ::Switchman::Shard.default.delayed_jobs_shard
      end
    end
  end
end
