class AddDelayedJobsMaxAttempts < ActiveRecord::Migration[4.2]
  def up
    add_column :delayed_jobs, :max_attempts, :integer
  end

  def down
    remove_column :delayed_jobs, :max_attempts
  end
end
