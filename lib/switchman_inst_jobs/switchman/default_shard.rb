module SwitchmanInstJobs
  module Switchman
    module DefaultShard
      def delayed_jobs_shard
        self
      end

      def jobs_held
        false
      end

      def block_stranded
        false
      end
    end
  end
end
