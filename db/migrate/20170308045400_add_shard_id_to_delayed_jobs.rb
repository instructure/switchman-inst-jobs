class AddShardIdToDelayedJobs < ActiveRecord::Migration
  disable_ddl_transaction!

  def connection
    Delayed::Backend::ActiveRecord::Job.connection
  end

  def up
    add_column :delayed_jobs, :shard_id, :integer, limit: 8
    add_index :delayed_jobs, :shard_id, algorithm: :concurrently

    add_column :failed_jobs, :shard_id, :integer, limit: 8
    add_index :failed_jobs, :shard_id, algorithm: :concurrently

    add_column :switchman_shards, :delayed_jobs_shard_id, :integer, limit: 8
    add_foreign_key(
      :switchman_shards,
      :switchman_shards,
      column: :delayed_jobs_shard_id
    )
  end

  def down
    remove_foreign_key :switchman_shards, column: :delayed_jobs_shard_id
    remove_column :switchman_shards, :delayed_jobs_shard_id

    remove_index :failed_jobs, :shard_id
    remove_column :failed_jobs, :shard_id

    remove_index :delayed_jobs, :shard_id
    remove_column :delayed_jobs, :shard_id
  end
end
