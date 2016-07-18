describe SwitchmanInstJobs::Shackles do
  it 'should not change environments during migrations' do
    ::ActiveRecord::Migration.verbose = false
    migration = Class.new(::ActiveRecord::Migration)

    def migration.up
      Shackles.activate(:slave) do
        @shackles_env = Shackles.environment
      end
    end

    Shackles.activate(:deploy) do
      migration.migrate(:up)
    end

    expect(migration.instance_variable_get(:@shackles_env)).to eq :deploy
  end

  it 'changes environments outside of migrations' do
    Shackles.activate(:deploy) do
      Shackles.activate(:slave) do
        expect(Shackles.environment).to eq :slave
      end
    end
  end
end
