# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../libnodectld/lib/nodectld/storage_effect_registry'

RSpec.describe StorageEffectRegistry do
  it 'classifies every loaded API transaction without an implicit default' do
    handles = Transaction.registered_types.select do |klass|
      klass.name.start_with?('Transactions::')
    end.map(&:t_type)

    expect(handles).to match_array(described_class::ENTRIES.keys)
    expect(handles).to all(satisfy { |handle| described_class.fetch!(handle) })
    expect do
      described_class.fetch!(99_999)
    end.to raise_error(described_class::Unclassified)
    expect(Transaction.registered_types.select(&:storage_effect).map(&:t_type)).to all(
      satisfy { |handle| described_class.fetch!(handle).admission_required }
    )
  end

  it 'rejects a second class registering the same numeric transaction handle' do
    original = Transaction.for_type(5204)
    expect do
      Transaction.register_type(5204, Class.new(Transaction))
    end.to raise_error(/duplicate transaction handle 5204/)
    expect(Transaction.for_type(5204)).to eq(original)
    expect(Transaction.register_type(5204, original)).to eq(original)
  end

  it 'has the same version, vocabulary and paired directions as NodeCtld' do
    node = NodeCtld::StorageEffectRegistry
    expect(node::VERSION).to eq(described_class::VERSION)
    expect(described_class::VERSION).to eq(4)
    expect(node::EFFECT_CLASSES).to eq(described_class::EFFECT_CLASSES)
    expect(node::VERIFICATION_IMPACTS).to eq(described_class::VERIFICATION_IMPACTS)
    expect(node::STRICT_SUPPORT_STATES).to eq(described_class::STRICT_SUPPORT_STATES)
    expect(described_class::ENTRIES.keys - node::ENTRIES.keys).to eq([5225])
    expect(node::ENTRIES.keys - described_class::ENTRIES.keys).to be_empty

    node::ENTRIES.each do |handle, entry|
      expect(entry.to_h).to eq(described_class.fetch!(handle).to_h)
      expect([entry.execute, entry.rollback] - described_class::EFFECT_CLASSES).to be_empty
      expect([entry.execute_impact, entry.rollback_impact] -
        described_class::VERIFICATION_IMPACTS).to be_empty
    end
    expect(described_class.fetch!(5225).support).to eq(:api_only_unsupported)
    expect(described_class.fetch!(5225).execute_strict_support).to eq(:unsupported)
  end

  it 'defaults mutating directions to unsupported strict dispatch' do
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
    %w[1001 5220 5223 5302 5405].map(&:to_i).each do |handle|
      expect(described_class.fetch!(handle).execute_strict_support).to eq(:unsupported)
    end
    expect(described_class.fetch!(5290).execute_strict_support).to eq(:proved_no_storage_effect)
  end

  it 'classifies both directions of the known topology and nested routes' do
    %w[1001 1002 2020 2029 2034 3001 3030 3031 3032 3033 3040 3041
       5208 5211 5212 5220 5223 5250 8001].map(&:to_i).each do |handle|
      entry = described_class.fetch!(handle)
      expect(entry.admission_required).to be(true)
      expect([entry.execute, entry.rollback]).to include(:opaque_topology)
    end
    expect(described_class.fetch!(1003).to_h).to include(
      execute: :opaque_topology, rollback: :no_storage,
      execute_impact: :physical_topology, rollback_impact: :none,
      admission_required: true
    )
    expect(described_class.fetch!(3035).to_h).to include(
      execute: :no_storage, rollback: :opaque_topology,
      execute_impact: :none, rollback_impact: :physical_topology,
      admission_required: true
    )
    expect(described_class.fetch!(5204).to_h).to include(
      execute: :bounded_topology, rollback: :bounded_topology,
      scope_resolver: :snapshot_create, guard_version: 1
    )
    expect(described_class.fetch!(5290).to_h).to include(
      execute: :read_only, rollback: :no_storage,
      execute_impact: :none, rollback_impact: :none, admission_required: false
    )
    %w[5004 5005 5301 5302 5303 5401 5402 5403 5404 5405 5406 5407]
      .map(&:to_i).each do |handle|
      expect(described_class.fetch!(handle).to_h).to include(
        execute: :data_or_property_write, rollback: :data_or_property_write,
        admission_required: true
      )
    end
    %w[2029 3031 3034 3303 5212 5228].map(&:to_i).each do |handle|
      expect(described_class.fetch!(handle).rollback).to eq(:no_storage)
      expect(described_class.fetch!(handle).rollback_impact).to eq(:none)
    end
  end

  it 'separates read-only admission from physical verification impact' do
    %w[2002 2003 5004 5005 5229 5261 5262 5263 5264].map(&:to_i).each do |handle|
      entry = described_class.fetch!(handle)
      expect(entry).to have_attributes(
        admission_required: true, execute_impact: :none,
        rollback_impact: :none, scope_resolver: :none
      )
    end
    %w[5216 5219 5226 5227 5228 5301 5302 5303 5401 5402 5403 5404 5405 5406 5407]
      .map(&:to_i).each do |handle|
      expect(described_class.fetch!(handle)).to have_attributes(
        execute_impact: :dependency, scope_resolver: :owner_pool
      )
    end
    expect(described_class.fetch!(5224)).to have_attributes(
      execute_impact: :catalog_identity, scope_resolver: :owner_pool
    )
    %w[7001 7002].map(&:to_i).each do |handle|
      expect(described_class.fetch!(handle)).to have_attributes(
        execute_impact: :physical_topology, scope_resolver: :node_pools
      )
    end
  end

  it 'admits catalog-only nested detachment before its NoOp command' do
    chain = TransactionChains::DatasetInPool::DetachBackupHeads
    expect(described_class.chain_admission_required?(chain)).to be(true)
    expect(described_class.fetch!(Transactions::Utils::NoOp.t_type).admission_required).to be(false)
    tagged = TransactionChain.descendants.select(&:storage_effect).map(&:name)
    expect(described_class::CHAIN_EFFECTS.keys).to match_array(tagged)
  end
end
