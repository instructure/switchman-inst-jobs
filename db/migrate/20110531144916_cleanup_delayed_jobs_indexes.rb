# frozen_string_literal: true

class CleanupDelayedJobsIndexes < ActiveRecord::Migration[4.2]
  def up
    case connection.adapter_name
    when "PostgreSQL"
      # "nulls first" syntax is postgresql specific, and allows for more
      # efficient querying for the next job
      connection.execute("CREATE INDEX get_delayed_jobs_index ON #{connection.quote_table_name(::Delayed::Job.table_name)} (priority, run_at, failed_at nulls first, locked_at nulls first, queue)")
    else
      add_index :delayed_jobs, %w[priority run_at locked_at failed_at queue], name: "get_delayed_jobs_index"
    end

    # unused indexes
    remove_index :delayed_jobs, name: "delayed_jobs_queue"
    remove_index :delayed_jobs, name: "delayed_jobs_priority"
  end

  def down
    remove_index :delayed_jobs, name: "get_delayed_jobs_index"
    add_index :delayed_jobs, %i[priority run_at], name: "delayed_jobs_priority"
    add_index :delayed_jobs, [:queue], name: "delayed_jobs_queue"
  end
end
