module SwitchmanInstJobs
  class TimedCache
    def initialize(timeout, &block)
      @timeout = timeout
      @block = block
      @cached_at = Time.zone.now
    end

    def clear(force = false)
      if force || @cached_at < @timeout.call
        @block.call
        @cached_at = Time.zone.now
        true
      else
        false
      end
    end
  end
end
