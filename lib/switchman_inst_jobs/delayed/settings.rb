# frozen_string_literal: true

module SwitchmanInstJobs
  module Delayed
    module Settings
      def self.configured_shard_ids
        (::Delayed::Settings.worker_config.try(:[], "workers") || []).pluck("shard").compact.uniq
      end
    end
  end
end
