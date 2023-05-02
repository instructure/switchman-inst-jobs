# frozen_string_literal: true

describe SwitchmanInstJobs::ActiveRecord::Migration do
  it "Has a copy of all delayed_engine migrations" do
    delayed_engine = Rails.application.railties.detect { |rt| rt.railtie_name == "delayed_engine" }
    delayed_migrations_path = delayed_engine.paths["db/migrate"].first
    delayed_migrations = if Rails.version >= "6"
                           ActiveRecord::MigrationContext.new(
                             delayed_migrations_path,
                             ActiveRecord::SchemaMigration
                           ).migrations
                         else
                           ActiveRecord::MigrationContext.new(
                             delayed_migrations_path
                           ).migrations
                         end

    switchman_inst_jobs_engine = Rails.application.railties.detect { |rt| rt.railtie_name == "switchman_inst_jobs" }
    switchman_inst_jobs_migrations_path = switchman_inst_jobs_engine.paths["db/migrate"].first
    switchman_inst_jobs_migrations = if Rails.version >= "6"
                                       ActiveRecord::MigrationContext.new(
                                         switchman_inst_jobs_migrations_path,
                                         ActiveRecord::SchemaMigration
                                       ).migrations
                                     else
                                       ActiveRecord::MigrationContext.new(
                                         switchman_inst_jobs_migrations_path
                                       ).migrations
                                     end

    expect(switchman_inst_jobs_migrations.map(&:name)).to include(*delayed_migrations.map(&:name))
  end
end
