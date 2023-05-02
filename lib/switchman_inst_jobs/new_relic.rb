# frozen_string_literal: true

module SwitchmanInstJobs
  module NewRelic
    module FixNewRelicDelayedJobs
      module NewRelicJobInvoker
        include ::NewRelic::Agent::Instrumentation::ControllerInstrumentation if defined?(::NewRelic)

        def invoke_job(*args, &block)
          options = {
            category: NR_TRANSACTION_CATEGORY,
            path: tag
          }

          perform_action_with_newrelic_trace(options) do
            super(*args, &block)
          end
        end
      end

      def install_newrelic_job_tracer
        ::Delayed::Job.prepend NewRelicJobInvoker
      end
    end

    def self.enable
      return unless defined?(::NewRelic)

      ::Delayed::Worker.prepend FixNewRelicDelayedJobs
    end
  end
end
