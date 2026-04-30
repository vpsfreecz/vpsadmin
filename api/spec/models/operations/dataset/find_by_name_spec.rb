# frozen_string_literal: true

require 'spec_helper'

RSpec.describe VpsAdmin::API::Operations::Dataset::FindByName do
  let(:pool) { create_pool!(node: SpecSeed.node, role: :primary) }
  let(:label) { "lookup-#{SecureRandom.hex(3)}" }
  let(:root_ds) do
    create_dataset_with_pool!(
      user: SpecSeed.user,
      pool: pool,
      name: "lookup-root-#{SecureRandom.hex(3)}",
      label: label
    ).first
  end
  let!(:child_ds) do
    create_dataset_with_pool!(
      user: SpecSeed.user,
      pool: pool,
      parent: root_ds,
      name: 'child'
    ).first
  end

  it 'finds datasets directly by full name' do
    expect(described_class.run(SpecSeed.user, child_ds.full_name)).to eq(child_ds)
  end

  it 'finds datasets by top-level label and path suffix' do
    expect(described_class.run(SpecSeed.user, "#{label}/child")).to eq(child_ds)
  end

  it 'raises for invalid dataset paths' do
    expect do
      described_class.run(SpecSeed.user, '')
    end.to raise_error(RuntimeError, 'invalid dataset path')
  end

  it 'raises for unknown labels' do
    expect do
      described_class.run(SpecSeed.user, 'unknown-label/child')
    end.to raise_error(ActiveRecord::RecordNotFound)
  end
end
