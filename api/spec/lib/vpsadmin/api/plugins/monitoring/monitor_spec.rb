# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'monitoring plugin monitor', requires_plugins: :monitoring do # rubocop:disable RSpec/DescribeClass
  def monitor_object(id:, user: nil)
    Struct.new(:id, :user).new(id, user)
  end

  it 'checks query results and reports against the resolved object' do
    owner = SpecSeed.user
    raw = monitor_object(id: 1, user: owner)
    real = monitor_object(id: 2, user: owner)
    monitor = build_monitor(
      :spec_monitor_check,
      query: -> { [raw] },
      object: ->(_obj) { real },
      value: ->(_obj) { 42 },
      check: ->(_obj, value) { value > 50 }
    )

    allow(MonitoredEvent).to receive(:report!)

    monitor.check

    expect(MonitoredEvent).to have_received(:report!).with(
      monitor,
      real,
      42,
      false,
      owner
    )
  end

  it 'selects responsible users from explicit proc, real object, and raw object' do
    explicit = SpecSeed.admin
    real_owner = SpecSeed.user
    raw_owner = SpecSeed.other_user
    raw = monitor_object(id: 1, user: raw_owner)
    real = monitor_object(id: 2, user: real_owner)

    allow(MonitoredEvent).to receive(:report!)

    build_monitor(
      :explicit_user,
      query: -> { [raw] },
      object: ->(_obj) { real },
      user: ->(_obj, _real_obj) { explicit }
    ).check
    build_monitor(
      :real_user,
      query: -> { [raw] },
      object: ->(_obj) { real }
    ).check
    build_monitor(
      :raw_user,
      query: -> { [raw] },
      object: ->(_obj) { Struct.new(:id).new(3) }
    ).check

    expect(MonitoredEvent).to have_received(:report!).with(anything, anything, anything, true, explicit)
    expect(MonitoredEvent).to have_received(:report!).with(anything, anything, anything, true, real_owner)
    expect(MonitoredEvent).to have_received(:report!).with(anything, anything, anything, true, raw_owner)
  end

  it 'calls configured actions and errors on unknown actions' do
    seen = nil
    VpsAdmin::API::Plugins::Monitoring.register_action(:spec_action, proc { |event| seen = event })
    monitor = build_monitor(:action_monitor, action: { confirmed: :spec_action, closed: :missing_action })
    chain = instance_double(TransactionChain)
    event = instance_double(MonitoredEvent)

    monitor.call_action(:confirmed, chain, event)

    expect(seen).to eq(event)
    expect do
      monitor.call_action(:closed, chain, event)
    end.to raise_error(RuntimeError, "unknown action 'missing_action'")
  end
end
