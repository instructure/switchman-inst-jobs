# frozen_string_literal: true

module SwitchmanInstJobs
  module Delayed
    module MessageSending
      def delay(sender: nil, synchronous: false, **enqueue_args)
        sender ||= __calculate_sender_for_delay
        synchronous ||= ::Switchman::DatabaseServer.creating_new_shard
        enqueue_args[:current_shard] = ::Switchman::Shard.current

        super
      end
    end
  end
end
