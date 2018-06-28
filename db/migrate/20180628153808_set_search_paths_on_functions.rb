class SetSearchPathsOnFunctions < ActiveRecord::Migration[4.2]
  disable_ddl_transaction!

  def up
    set_search_path('delayed_jobs_after_delete_row_tr_fn', '()')
    set_search_path('delayed_jobs_before_insert_row_tr_fn', '()')
    set_search_path('half_md5_as_bigint', '(varchar)')
  end

  def down
    set_search_path('delayed_jobs_after_delete_row_tr_fn', '()', 'DEFAULT')
    set_search_path('delayed_jobs_before_insert_row_tr_fn', '()', 'DEFAULT')
    set_search_path('half_md5_as_bigint', '(varchar)', 'DEFAULT')
  end
end
