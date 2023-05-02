# frozen_string_literal: true

class CopyFailedJobsOriginalId < ActiveRecord::Migration[4.2]
  def up
    # Noop since we don't want to modify the shard using a different connection than the one we are using to build it and
    # this migration is very old
  end

  def down; end
end
