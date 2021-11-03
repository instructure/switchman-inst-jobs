class AddShardIdToDelayedJobs < ActiveRecord::Migration[4.2]
  disable_ddl_transaction!

  def up
    add_column :delayed_jobs, :shard_id, :integer, limit: 8
    add_index :delayed_jobs, :shard_id, algorithm: :concurrently

    add_column :failed_jobs, :shard_id, :integer, limit: 8
    add_index :failed_jobs, :shard_id, algorithm: :concurrently
  end

  def down
    remove_index :failed_jobs, :shard_id
    remove_column :failed_jobs, :shard_id

    remove_index :delayed_jobs, :shard_id
    remove_column :delayed_jobs, :shard_id
  end
end
