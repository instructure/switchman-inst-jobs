describe SwitchmanInstJobs::GuardRail do
  it 'should not change environments during migrations' do
    ::ActiveRecord::Migration.verbose = false
    migration = Class.new(::ActiveRecord::Migration[4.2])

    def migration.up
      GuardRail.activate(:secondary) do
        @guard_rail_env = GuardRail.environment
      end
    end

    GuardRail.activate(:deploy) do
      migration.migrate(:up)
    end

    expect(migration.instance_variable_get(:@guard_rail_env)).to eq :deploy
  end

  it 'changes environments outside of migrations' do
    GuardRail.activate(:deploy) do
      GuardRail.activate(:secondary) do
        expect(GuardRail.environment).to eq :secondary
      end
    end
  end
end
