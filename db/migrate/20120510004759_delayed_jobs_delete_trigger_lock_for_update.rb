# frozen_string_literal: true

class DelayedJobsDeleteTriggerLockForUpdate < ActiveRecord::Migration[4.2]
  def up
    if connection.adapter_name == "PostgreSQL"
      execute(<<~SQL)
        CREATE OR REPLACE FUNCTION #{connection.quote_table_name("delayed_jobs_after_delete_row_tr_fn")} () RETURNS trigger AS $$
        BEGIN
          UPDATE delayed_jobs SET next_in_strand = 't' WHERE id = (SELECT id FROM delayed_jobs j2 WHERE j2.strand = OLD.strand ORDER BY j2.strand, j2.id ASC LIMIT 1 FOR UPDATE);
          RETURN OLD;
        END;
        $$ LANGUAGE plpgsql SET search_path TO #{::Switchman::Shard.current.name};
      SQL
    end
  end

  def down
    if connection.adapter_name == "PostgreSQL"
      execute(<<~SQL)
        CREATE OR REPLACE FUNCTION #{connection.quote_table_name("delayed_jobs_after_delete_row_tr_fn")} () RETURNS trigger AS $$
        BEGIN
          UPDATE delayed_jobs SET next_in_strand = 't' WHERE id = (SELECT id FROM delayed_jobs j2 WHERE j2.strand = OLD.strand ORDER BY j2.strand, j2.id ASC LIMIT 1);
          RETURN OLD;
        END;
        $$ LANGUAGE plpgsql SET search_path TO #{::Switchman::Shard.current.name};
      SQL
    end
  end
end
