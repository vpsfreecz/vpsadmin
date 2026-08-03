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
