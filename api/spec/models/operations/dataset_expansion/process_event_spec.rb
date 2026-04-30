# frozen_string_literal: true

require 'spec_helper'

RSpec.describe VpsAdmin::API::Operations::DatasetExpansion::ProcessEvent do
  around do |example|
    with_current_context(user: SpecSeed.admin) { example.run }
  end

  def create_event!(dataset:, original_refquota: 10_240, added_space: 1024)
    DatasetExpansionEvent.create!(
      dataset: dataset,
      original_refquota: original_refquota,
      added_space: added_space,
      new_refquota: original_refquota + added_space
    )
  end

  def diskspace_resource_for(user, environment)
    UserClusterResource.joins(:cluster_resource).find_by!(
      user: user,
      environment: environment,
      cluster_resources: { name: 'diskspace' }
    )
  end

  it 'deletes and ignores events without a dataset' do
    event = DatasetExpansionEvent.new(
      dataset: nil,
      original_refquota: 10_240,
      added_space: 1024,
      new_refquota: 11_264
    )

    expect(described_class.run(event, max_over_refquota_seconds: 3600)).to be_nil
    expect(event).to be_destroyed
  end

  it 'deletes and ignores events whose dataset has no primary DatasetInPool' do
    dataset = Dataset.create!(
      user: SpecSeed.user,
      name: "orphan-#{SecureRandom.hex(3)}",
      user_editable: true,
      user_create: true,
      user_destroy: true,
      confirmed: Dataset.confirmed(:confirmed)
    )
    event = create_event!(dataset: dataset)

    expect(described_class.run(event, max_over_refquota_seconds: 3600)).to be_nil
    expect(DatasetExpansionEvent.exists?(event.id)).to be(false)
  end

  it 'creates a resolved expansion, history row and deletes the event when under limit' do
    fixture = build_standalone_vps_fixture(user: SpecSeed.user, diskspace: 10_240)
    event = create_event!(dataset: fixture.fetch(:dataset), original_refquota: 10_240, added_space: 1024)
    expansion = nil

    expect do
      expansion = described_class.run(event, max_over_refquota_seconds: 3600)
    end.to change(DatasetExpansion, :count).by(1)
                                           .and change(DatasetExpansionHistory, :count).by(1)

    expansion.reload
    expect(expansion).to be_resolved
    expect(expansion.original_refquota).to eq(10_240)
    expect(expansion.added_space).to eq(1024)
    expect(expansion.max_over_refquota_seconds).to eq(3600)
    expect(fixture.fetch(:dataset).reload.dataset_expansion).to be_nil
    expect(fixture.fetch(:dataset_in_pool).reload.refquota).to eq(11_264)
    expect(DatasetExpansionEvent.exists?(event.id)).to be(false)
    expect(expansion.dataset_expansion_histories.last).to have_attributes(
      original_refquota: 10_240,
      new_refquota: 11_264,
      added_space: 1024
    )
  end

  it 'accumulates added space on an existing active expansion' do
    fixture = build_active_dataset_expansion_fixture(
      user: SpecSeed.user,
      original_refquota: 10_240,
      added_space: 2048
    )
    event = create_event!(
      dataset: fixture.fetch(:dataset),
      original_refquota: fixture.fetch(:current_refquota),
      added_space: 1024
    )

    ret = described_class.run(event, max_over_refquota_seconds: 3600)

    expect(ret).to eq(fixture.fetch(:expansion))
    expect(ret.reload.added_space).to eq(3072)
    expect(ret.dataset_expansion_histories.order(:id).last).to have_attributes(
      original_refquota: fixture.fetch(:current_refquota),
      new_refquota: fixture.fetch(:current_refquota) + 1024,
      added_space: 1024
    )
    expect(DatasetExpansionEvent.exists?(event.id)).to be(false)
  end

  it 'marks over-limit expansions active and attaches them to the dataset' do
    fixture = build_standalone_vps_fixture(user: SpecSeed.user, diskspace: 10_240)
    environment = fixture.fetch(:pool).node.location.environment
    diskspace_resource_for(SpecSeed.user, environment).update!(value: 11_000)
    event = create_event!(dataset: fixture.fetch(:dataset), original_refquota: 10_240, added_space: 2048)

    expansion = described_class.run(event, max_over_refquota_seconds: 7200).reload

    expect(expansion).to be_active
    expect(expansion.max_over_refquota_seconds).to eq(7200)
    expect(fixture.fetch(:dataset).reload.dataset_expansion).to eq(expansion)
  end

  it 'bubbles ResourceLocked without deleting the event' do
    fixture = build_standalone_vps_fixture(user: SpecSeed.user)
    event = DatasetExpansionEvent.new(
      dataset: fixture.fetch(:dataset),
      original_refquota: 10_240,
      added_space: 1024,
      new_refquota: 11_264
    )
    dip = fixture.fetch(:dataset_in_pool)

    allow(fixture.fetch(:dataset)).to receive(:primary_dataset_in_pool!).and_return(dip)
    allow(dip).to receive(:acquire_lock).and_raise(ResourceLocked.new(dip, 'locked'))

    expect do
      described_class.run(event, max_over_refquota_seconds: 3600)
    end.to raise_error(ResourceLocked, 'locked')

    expect(event).not_to be_destroyed
  end
end
