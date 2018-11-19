require 'inst-jobs'
require 'switchman'

module SwitchmanInstJobs
  def self.initialize_active_record
    ::ActiveRecord::ConnectionAdapters::PostgreSQLAdapter.prepend(
      ActiveRecord::ConnectionAdapters::PostgreSQLAdapter
    )
  end

  def self.initialize_inst_jobs
    ::Delayed::Backend::ActiveRecord::Job.prepend(
      Delayed::Backend::Base
    )
    ::Delayed::Backend::Redis::Job.prepend(
      Delayed::Backend::Base
    )
    ::Delayed::Backend::Redis::Job.column :shard_id, :integer
    ::Delayed::Pool.prepend Delayed::Pool
    ::Delayed::Worker.prepend Delayed::Worker
    ::Delayed::Worker::HealthCheck.prepend Delayed::Worker::HealthCheck
    ::Object.include Delayed::MessageSending
  end

  def self.initialize_shackles
    ::Shackles.singleton_class.prepend Shackles::ClassMethods
  end

  def self.initialize_switchman
    ::Switchman::DatabaseServer.prepend Switchman::DatabaseServer
    ::Switchman::DefaultShard.prepend Switchman::DefaultShard
    ::Switchman::Shard.prepend Switchman::Shard
  end
end

require 'switchman_inst_jobs/active_record/connection_adapters/postgresql_adapter'
require 'switchman_inst_jobs/active_record/migration'
require 'switchman_inst_jobs/delayed/backend/base'
require 'switchman_inst_jobs/delayed/message_sending'
require 'switchman_inst_jobs/delayed/pool'
require 'switchman_inst_jobs/delayed/worker'
require 'switchman_inst_jobs/delayed/worker/health_check'
require 'switchman_inst_jobs/engine'
require 'switchman_inst_jobs/shackles'
require 'switchman_inst_jobs/switchman/database_server'
require 'switchman_inst_jobs/switchman/default_shard'
require 'switchman_inst_jobs/switchman/shard'
require 'switchman_inst_jobs/yaml_extensions'
