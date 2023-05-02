# frozen_string_literal: true

class DropFailedJobsOriginalId < ActiveRecord::Migration[4.2]
  def up
    remove_column :failed_jobs, :original_id
  end

  def down
    add_column :failed_jobs, :original_id, :integer, limit: 8
  end
end
