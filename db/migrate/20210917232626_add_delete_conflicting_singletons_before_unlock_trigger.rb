# frozen_string_literal: true

class AddDeleteConflictingSingletonsBeforeUnlockTrigger < ActiveRecord::Migration[5.2]
  def up
    execute(<<~SQL)
      CREATE FUNCTION #{connection.quote_table_name('delayed_jobs_before_unlock_delete_conflicting_singletons_row_fn')} () RETURNS trigger AS $$
      BEGIN
        IF EXISTS (SELECT 1 FROM delayed_jobs j2 WHERE j2.singleton=OLD.singleton) THEN
          DELETE FROM delayed_jobs WHERE id<>OLD.id AND singleton=OLD.singleton;
        END IF;
        RETURN NEW;
      END;
      $$ LANGUAGE plpgsql SET search_path TO #{::Switchman::Shard.current.name};
    SQL
    execute(<<~SQL)
      CREATE TRIGGER delayed_jobs_before_unlock_delete_conflicting_singletons_row_tr BEFORE UPDATE ON #{::Delayed::Job.quoted_table_name} FOR EACH ROW WHEN (
        OLD.singleton IS NOT NULL AND
        OLD.singleton=NEW.singleton AND
        OLD.locked_by IS NOT NULL AND
        NEW.locked_by IS NULL) EXECUTE PROCEDURE #{connection.quote_table_name('delayed_jobs_before_unlock_delete_conflicting_singletons_row_fn')}();
    SQL
  end

  def down
    execute("DROP FUNCTION #{connection.quote_table_name('delayed_jobs_before_unlock_delete_conflicting_singletons_row_tr_fn')}() CASCADE")
  end
end
