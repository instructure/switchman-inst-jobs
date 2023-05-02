# frozen_string_literal: true

class AddDelayedJobsShardIdToSwitchmanShards < ActiveRecord::Migration[5.2]
  def change
    add_reference :switchman_shards, :delayed_jobs_shard, foreign_key: { to_table: :switchman_shards }, index: false, if_not_exists: true
  end
end
