# frozen_string_literal: true

require 'spec_helper'

class FakeMigrationPlan
  attr_reader :state, :vps_migration

  def initialize(state: 'staged', result: FakeRecord.new(ok: true))
    @state = state
    @result = result
    @vps_migration = FakeCollection.new
  end

  def start
    @result
  end
end

class FakeMigrationPlanCollection
  attr_reader :created, :found

  def initialize(plan)
    @plan = plan
    @created = []
  end

  def create(opts)
    @created << opts
    @plan
  end

  def find(id)
    @found = id
    @plan
  end
end

RSpec.describe VpsAdmin::CLI::Commands::VpsMigrateMany do
  def command_with(api:, opts:)
    described_class.allocate.tap do |command|
      command.instance_variable_set(:@api, api)
      command.instance_variable_set(:@opts, opts)
    end
  end

  it 'creates a plan, schedules each VPS, and starts it' do
    plan = FakeMigrationPlan.new(result: FakeRecord.new(started: true))
    plans = FakeMigrationPlanCollection.new(plan)
    api = FakeRecord.new(migration_plan: plans)
    command = command_with(
      api: api,
      opts: {
        dst_node: 7,
        outage_window: false,
        cleanup_data: true,
        reason: 'maintenance'
      }
    )

    allow(HaveAPI::CLI::OutputFormatter).to receive(:print)

    capture_stdout { command.exec(%w[101 102]) }

    expect(plans.created).to eq([
                                  {
                                    dst_node: 7,
                                    outage_window: false,
                                    cleanup_data: true,
                                    reason: 'maintenance'
                                  }
                                ])
    expect(plan.vps_migration.created).to eq([
                                               { vps: 101, dst_node: 7, outage_window: false, cleanup_data: true },
                                               { vps: 102, dst_node: 7, outage_window: false, cleanup_data: true }
                                             ])
    expect(HaveAPI::CLI::OutputFormatter).to have_received(:print).with(started: true)
  end

  it 'reuses an existing staged plan' do
    plan = FakeMigrationPlan.new
    plans = FakeMigrationPlanCollection.new(plan)
    api = FakeRecord.new(migration_plan: plans)
    command = command_with(api: api, opts: { plan: '55', dst_node: 7 })

    allow(HaveAPI::CLI::OutputFormatter).to receive(:print)

    capture_stdout { command.exec(%w[101 102]) }

    expect(plans.found).to eq('55')
    expect(plans.created).to be_empty
    expect(plan.vps_migration.created.map { |params| params[:vps] }).to eq([101, 102])
  end
end
