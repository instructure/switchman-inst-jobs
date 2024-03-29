# frozen_string_literal: true

class AddJobsRunAtIndex < ActiveRecord::Migration[4.2]
  disable_ddl_transaction!

  def up
    add_index :delayed_jobs, %w[run_at tag], algorithm: :concurrently
  end

  def down
    remove_index :delayed_jobs, name: "index_delayed_jobs_on_run_at_and_tag"
  end
end
