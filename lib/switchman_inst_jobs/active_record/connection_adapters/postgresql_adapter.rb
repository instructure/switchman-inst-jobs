# frozen_string_literal: true

module SwitchmanInstJobs
  module ActiveRecord
    module ConnectionAdapters
      module PostgreSQLAdapter
        def set_search_path(function, args = "()", path = ::Switchman::Shard.current.name)
          execute <<-SQL
            ALTER FUNCTION #{quote_table_name(function)}#{args}
              SET search_path TO #{path}
          SQL
        end
      end
    end
  end
end
