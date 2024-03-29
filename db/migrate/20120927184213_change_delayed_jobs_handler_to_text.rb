# frozen_string_literal: true

class ChangeDelayedJobsHandlerToText < ActiveRecord::Migration[4.2]
  def up
    change_column :delayed_jobs, :handler, :text
  end

  def down
    change_column :delayed_jobs, :handler, :string, limit: 500.kilobytes
  end
end
