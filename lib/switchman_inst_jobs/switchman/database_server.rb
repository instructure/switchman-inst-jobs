module SwitchmanInstJobs
  module Switchman
    module DatabaseServer
      def delayed_jobs_shard(shard = nil)
        return shard if config[:delayed_jobs_shard] == 'self'
        dj_shard =
          config[:delayed_jobs_shard] &&
          ::Switchman::Shard.lookup(config[:delayed_jobs_shard])
        # have to avoid recursion for the default shard asking for the default
        # shard's delayed_jobs_shard
        dj_shard ||= shard if shard&.default?
        dj_shard || ::Switchman::Shard.default.delayed_jobs_shard
      end
    end
  end
end
