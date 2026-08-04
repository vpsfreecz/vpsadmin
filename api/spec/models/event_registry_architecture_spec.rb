require_relative '../spec_helper'

RSpec.describe VpsAdmin::API::Events do
  it 'retains the declaration owner on the public event type' do
    name = 'spec.architecture_owner'
    definition = described_class::EventDefinition.new(
      name,
      owner: :architecture_spec,
      label: 'Architecture owner spec',
      category: :general,
      default_routed: false,
      roles: [:admin]
    )

    described_class.add_definition(definition)

    expect(described_class.type_for(name).owner).to eq(:architecture_spec)
  ensure
    described_class.instance_variable_get(:@types).delete(name)
  end

  it 'rejects a duplicate event name without replacing the first definition' do
    name = 'spec.duplicate_definition'
    first = described_class::EventDefinition.new(
      name,
      owner: :first_spec,
      label: 'First definition',
      category: :general,
      default_routed: false,
      roles: [:admin]
    )
    second = described_class::EventDefinition.new(
      name,
      owner: :second_spec,
      label: 'Second definition',
      category: :general,
      default_routed: false,
      roles: [:admin]
    )

    described_class.add_definition(first)

    expect { described_class.add_definition(second) }
      .to raise_error(ArgumentError, /already defined by first_spec/)
    expect(described_class.type_for(name).label).to eq('First definition')
  ensure
    described_class.instance_variable_get(:@types).delete(name)
  end

  it 'keeps repeated monitoring profile objects idempotent and rejects conflicts atomically',
     requires_plugins: :monitoring do
    events = VpsAdmin::API::Plugins::Monitoring::Events
    event_name = 'monitoring.architecture_spec'
    conflicting_event_name = 'monitoring.architecture_conflict_spec'
    monitor_name = 'architecture_spec'
    attributes = {
      label: 'Architecture monitoring spec',
      template: :alert_monitoring_spec,
      monitors: [monitor_name],
      fields: [:vps]
    }

    first_type = events.register_event(event_name, **attributes)
    first_profile = events.event_profiles.fetch(event_name)
    first_monitor_mapping = events.monitor_event_types.fetch(monitor_name)

    expect(events.register_event(event_name, **attributes)).to equal(first_type)
    expect(events.event_profiles.fetch(event_name)).to equal(first_profile)

    expect do
      events.register_event(
        event_name,
        **attributes,
        label: 'Conflicting architecture monitoring spec'
      )
    end.to raise_error(ArgumentError, /conflicts with its existing profile/)
    expect(events.event_profiles.fetch(event_name)).to equal(first_profile)
    expect(events.monitor_event_types.fetch(monitor_name)).to eq(first_monitor_mapping)
    expect(described_class.type_for(event_name)).to equal(first_type)

    expect do
      events.register_event(
        conflicting_event_name,
        **attributes,
        monitors: [monitor_name]
      )
    end.to raise_error(ArgumentError, /monitor .* is already assigned to/)
    expect(events.event_profiles).not_to have_key(conflicting_event_name)
    expect(events.monitor_event_types.fetch(monitor_name)).to eq(first_monitor_mapping)
    expect(described_class.type_for(conflicting_event_name)).to be_nil
  ensure
    events&.event_profiles&.delete(event_name)
    events&.event_profiles&.delete(conflicting_event_name)
    events&.monitor_event_types&.delete(monitor_name)
    described_class.instance_variable_get(:@types).delete(event_name)
    described_class.instance_variable_get(:@types).delete(conflicting_event_name)
  end

  it 'infers fallback policies for actions without the policy declaration DSL' do
    action = Class.new do
      define_singleton_method(:http_method) { :post }
      define_singleton_method(:blocking) { true }
      define_singleton_method(:model) { OsFamily }
    end

    expect(VpsAdmin::API::Events::ActionPolicies.for(action)).to have_attributes(
      kind: :transaction_chain,
      models: ['OsFamily'],
      atomic: false
    )
  end

  it 'does not mask errors raised by an explicit action policy declaration' do
    action = Class.new do
      define_singleton_method(:event_policy) do
        raise NoMethodError, 'malformed explicit event policy'
      end
    end

    expect do
      VpsAdmin::API::Events::ActionPolicies.for(action)
    end.to raise_error(NoMethodError, /malformed explicit event policy/)
  end

  it 'merges generic plugin i18n extensions and rejects duplicate owners' do
    owner = :architecture_i18n_spec
    extensions = described_class.instance_variable_get(:@i18n_default_extensions)
    described_class.register_i18n_defaults(owner) do
      { 'events.types.architecture_spec.label' => 'Architecture spec' }
    end

    expect(described_class.i18n_defaults)
      .to include('events.types.architecture_spec.label' => 'Architecture spec')
    expect { described_class.register_i18n_defaults(owner) { {} } }
      .to raise_error(ArgumentError, /already registered/)
  ensure
    extensions.delete(owner) if extensions
  end
end
