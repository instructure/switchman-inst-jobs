# frozen_string_literal: true

module SwitchmanInstJobs
  module Switchman
    module DefaultShard
      def delayed_jobs_shard
        self
      end

      def jobs_held # rubocop:disable Naming/PredicateMethod
        false
      end

      def block_stranded # rubocop:disable Naming/PredicateMethod
        false
      end
    end
  end
end
