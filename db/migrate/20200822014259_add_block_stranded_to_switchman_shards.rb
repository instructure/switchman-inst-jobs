class AddBlockStrandedToSwitchmanShards < ActiveRecord::Migration[5.2]
  def change
    add_column :switchman_shards, :block_stranded, :bool, default: false
  end
end
