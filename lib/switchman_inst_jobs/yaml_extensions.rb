module SwitchmanInstJobs
  module PsychExt
    module ToRuby
      def visit_Psych_Nodes_Scalar(object) # rubocop:disable Naming/MethodName
        if object.tag == '!ruby/ActiveRecord:Switchman::Shard'
          ::Switchman::Shard.lookup(object.value) ||
            raise(Delayed::Backend::RecordNotFound,
              "Couldn't find Switchman::Shard with id #{object.value.inspect}")
        else
          super
        end
      end
    end
  end
end
Psych::Visitors::ToRuby.prepend(SwitchmanInstJobs::PsychExt::ToRuby)
