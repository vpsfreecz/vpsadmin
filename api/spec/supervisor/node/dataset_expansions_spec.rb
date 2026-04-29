# frozen_string_literal: true

require 'spec_helper'

RSpec.describe VpsAdmin::Supervisor::Node::DatasetExpansions do
  let(:node) { SpecSeed.node }
  let(:supervisor) { described_class.new(nil, node) }
  let(:timestamp) { Time.utc(2026, 4, 5, 16, 0, 0) }
  let(:operation) { VpsAdmin::API::Operations::DatasetExpansion::ProcessEvent }

  def expansion_event(fixture, overrides = {})
    {
      'dataset_id' => fixture.fetch(:dataset).id,
      'original_refquota' => 10_240,
      'new_refquota' => 12_288,
      'added_space' => 2048,
      'time' => timestamp.to_i
    }.merge(overrides)
  end

  before do
    allow(TransactionChains::Mail::VpsDatasetExpanded).to receive(:fire)
  end

  describe '#process_event' do
    it 'ignores expansions whose primary pool is not on the current node' do
      fixture = build_active_dataset_expansion_fixture(user: SpecSeed.other_user)
      fixture.fetch(:dataset_in_pool).update!(pool: create_pool!(node: SpecSeed.other_node, role: :hypervisor))
      allow(operation).to receive(:run)

      supervisor.send(:process_event, expansion_event(fixture))

      expect(operation).not_to have_received(:run)
      expect(DatasetExpansionEvent.where(dataset: fixture.fetch(:dataset))).to be_empty
    end

    it 'processes the event and schedules notification mail for active VPSes' do
      fixture = build_active_dataset_expansion_fixture(enable_notifications: true)
      expansion = fixture.fetch(:expansion)
      allow(operation).to receive(:run).and_return(expansion)

      supervisor.send(:process_event, expansion_event(fixture))

      expect(operation).to have_received(:run).with(
        instance_of(DatasetExpansionEvent),
        max_over_refquota_seconds: VpsAdmin::API::Tasks::DatasetExpansion::MAX_OVER_REFQUOTA_SECONDS
      )
      expect(TransactionChains::Mail::VpsDatasetExpanded).to have_received(:fire).with(expansion)
      expect(DatasetExpansionEvent.where(dataset: fixture.fetch(:dataset))).to be_empty
    end

    it 'persists the event when processing is locked' do
      fixture = build_active_dataset_expansion_fixture
      allow(operation).to receive(:run)
        .and_raise(ResourceLocked.new(fixture.fetch(:dataset), 'locked'))

      supervisor.send(:process_event, expansion_event(fixture))

      saved = DatasetExpansionEvent.find_by!(dataset: fixture.fetch(:dataset))
      expect(saved.original_refquota).to eq(10_240)
      expect(saved.new_refquota).to eq(12_288)
      expect(saved.added_space).to eq(2048)
      expect(saved.created_at).to eq(timestamp)
      expect(TransactionChains::Mail::VpsDatasetExpanded).not_to have_received(:fire)
    end

    it 'does not schedule mail when notifications are disabled' do
      fixture = build_active_dataset_expansion_fixture(enable_notifications: false)
      expansion = fixture.fetch(:expansion)
      allow(operation).to receive(:run).and_return(expansion)

      supervisor.send(:process_event, expansion_event(fixture))

      expect(TransactionChains::Mail::VpsDatasetExpanded).not_to have_received(:fire)
    end
  end
end
