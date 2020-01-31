module SwitchmanInstJobs
  module Delayed
    module MessageSending
      def send_later_enqueue_args(method, _enqueue_args = {}, *args)
        return send(method, *args) if ::Switchman::DatabaseServer.creating_new_shard

        super
      end
    end
  end
end
