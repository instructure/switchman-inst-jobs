# frozen_string_literal: true

class AddMigrateFromJobsShard < ActiveRecord::Migration[7.1]
  def change
    add_reference :switchman_shards, :migrate_from_delayed_jobs_shard, foreign_key: { to_table: :switchman_shards }, index: false, if_not_exists: true
  end
end
