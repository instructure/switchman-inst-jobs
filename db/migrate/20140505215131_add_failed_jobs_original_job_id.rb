class AddFailedJobsOriginalJobId < ActiveRecord::Migration[4.2]
  def up
    add_column :failed_jobs, :original_job_id, :integer, limit: 8
  end

  def down
    remove_column :failed_jobs, :original_job_id
  end
end
