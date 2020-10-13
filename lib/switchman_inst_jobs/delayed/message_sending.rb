module SwitchmanInstJobs
  module Delayed
    module MessageSending
      def delay(**enqueue_args)
        return self if ::Switchman::DatabaseServer.creating_new_shard

        super
      end
    end
  end
end
