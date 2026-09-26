# frozen_string_literal: true

require 'spec_helper'
require 'nodectld'

RSpec.describe NodeCtld::StorageEffectRegistry do
  it 'classifies every normally loaded command handler' do
    production = NodeCtld::Command.registered_handlers.select do |_handle, klass|
      klass.start_with?('NodeCtld::Commands::')
    end

    expect(production.keys).to match_array(described_class::ENTRIES.keys)
    expect do
      described_class.fetch!(5225)
    end.to raise_error(described_class::Unclassified)
  end

  it 'rejects a second class registering the same numeric command handle' do
    original = NodeCtld::Command.registered_handlers.fetch(5204)
    expect do
      NodeCtld::Command.register('NodeCtld::Commands::Other', 5204)
    end.to raise_error(/duplicate command handle 5204/)
    expect(NodeCtld::Command.registered_handlers.fetch(5204)).to eq(original)
    expect(NodeCtld::Command.register(original, 5204)).to eq(original)
  end

  it 'covers direct nested command and osctl topology routes in both directions' do
    expect(described_class.fetch!(3001).rollback).to eq(:opaque_topology) # nested Destroy
    expect(described_class.fetch!(5219).rollback).to eq(:data_or_property_write) # nested Set
    expect(described_class.fetch!(5302).rollback).to eq(:data_or_property_write) # nested Umount
    expect(described_class.fetch!(5303).rollback).to eq(:data_or_property_write) # nested Mount
    expect(described_class.fetch!(2020).to_h).to include(
      execute: :opaque_topology, rollback: :opaque_topology
    )
    expect(described_class.fetch!(3030).rollback).to eq(:opaque_topology) # ct send cancel
    expect(described_class.fetch!(3035).rollback).to eq(:opaque_topology) # ct del
    expect(described_class.fetch!(1003).rollback).to eq(:no_storage)
    expect(described_class.fetch!(1003).rollback_impact).to eq(:none)
    %w[2029 3031 3034 3303 5212 5228].map(&:to_i).each do |handle|
      expect(described_class.fetch!(handle).rollback).to eq(:no_storage)
      expect(described_class.fetch!(handle).rollback_impact).to eq(:none)
    end
    expect(described_class.fetch!(7001)).to have_attributes(
      execute_impact: :physical_topology, scope_resolver: :node_pools
    )
    expect(described_class.fetch!(5405)).to have_attributes(
      execute_impact: :dependency, scope_resolver: :owner_pool
    )
    (5401..5407).each do |handle|
      expect(described_class.fetch!(handle).to_h).to include(
        execute: :data_or_property_write, rollback: :data_or_property_write,
        admission_required: true
      )
    end
  end

  it 'refuses unsupported directions under the version-five test policy' do
    expect(described_class::VERSION).to eq(5)
    expect(described_class.fetch!(5204)).to have_attributes(
      execute_strict_support: :guarded_5204_v1,
      rollback_strict_support: :guarded_5204_v1
    )
    expect(described_class.fetch!(5215)).to have_attributes(
      execute_strict_support: :guarded_5215_v1,
      rollback_strict_support: :guarded_5215_v1
    )
    expect(described_class.fetch!(5212)).to have_attributes(
      execute_strict_support: :unsupported,
      rollback_strict_support: :proved_no_storage_effect
    )
    %w[1001 5220 5223].map(&:to_i).each do |handle|
      expect(described_class.fetch!(handle).execute_strict_support).to eq(:unsupported)
    end
    expect(described_class.fetch!(5291).to_h).to include(
      execute: :read_only, rollback: :no_storage,
      execute_impact: :none, rollback_impact: :none,
      admission_required: false, execute_strict_support: :proved_no_storage_effect,
      rollback_strict_support: :proved_no_storage_effect
    )
  end
end
