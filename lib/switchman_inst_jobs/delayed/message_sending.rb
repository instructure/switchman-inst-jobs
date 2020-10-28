module SwitchmanInstJobs
  module Delayed
    module MessageSending
      def delay(public_send: nil, synchronous: false, **enqueue_args)
        public_send ||= __calculate_public_send_for_delay
        synchronous ||= ::Switchman::DatabaseServer.creating_new_shard

        super
      end
    end
  end
end
