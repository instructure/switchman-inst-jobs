class AddOnHoldToSwitchmanShards < ActiveRecord::Migration[5.2]
  def change
    add_column :switchman_shards, :jobs_held, :bool, default: false
  end
end
