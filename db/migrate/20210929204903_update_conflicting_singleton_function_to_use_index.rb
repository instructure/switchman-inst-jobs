# frozen_string_literal: true

class UpdateConflictingSingletonFunctionToUseIndex < ActiveRecord::Migration[5.2]
  def up
    execute(<<~SQL)
      CREATE OR REPLACE FUNCTION #{connection.quote_table_name("delayed_jobs_before_unlock_delete_conflicting_singletons_row_fn")} () RETURNS trigger AS $$
      BEGIN
        DELETE FROM delayed_jobs WHERE id<>OLD.id AND singleton=OLD.singleton AND locked_by IS NULL;
        RETURN NEW;
      END;
      $$ LANGUAGE plpgsql SET search_path TO #{::Switchman::Shard.current.name};
    SQL
  end

  def down
    execute(<<~SQL)
      CREATE OR REPLACE FUNCTION #{connection.quote_table_name("delayed_jobs_before_unlock_delete_conflicting_singletons_row_fn")} () RETURNS trigger AS $$
      BEGIN
        IF EXISTS (SELECT 1 FROM delayed_jobs j2 WHERE j2.singleton=OLD.singleton) THEN
          DELETE FROM delayed_jobs WHERE id<>OLD.id AND singleton=OLD.singleton;
        END IF;
        RETURN NEW;
      END;
      $$ LANGUAGE plpgsql SET search_path TO #{::Switchman::Shard.current.name};
    SQL
  end
end
