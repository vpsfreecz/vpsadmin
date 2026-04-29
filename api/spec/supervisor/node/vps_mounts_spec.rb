# frozen_string_literal: true

require 'spec_helper'

RSpec.describe VpsAdmin::Supervisor::Node::VpsMounts do
  let(:node) { SpecSeed.node }
  let(:supervisor) { described_class.new(nil, node) }
  let(:timestamp) { Time.utc(2026, 4, 5, 19, 0, 0) }

  def mount_state_payload(vps, id:, state:)
    {
      'id' => id,
      'vps_id' => vps.id,
      'state' => state,
      'time' => timestamp.to_i
    }
  end

  def create_mount_fixture
    fixture = build_standalone_vps_fixture(node:)
    vps = fixture.fetch(:vps)
    _subdataset, sub_dip = create_vps_subdataset!(
      user: vps.user,
      pool: fixture.fetch(:pool),
      parent: fixture.fetch(:dataset)
    )

    [
      vps,
      create_mount_record!(vps:, dataset_in_pool: sub_dip, dst: '/mnt/one'),
      create_mount_record!(vps:, dataset_in_pool: sub_dip, dst: '/mnt/two')
    ]
  end

  describe '#update_mount_state' do
    it 'updates all mounts for a VPS when id is all' do
      vps, first, second = create_mount_fixture
      other_vps, other_mount = create_mount_fixture

      supervisor.send(:update_mount_state, mount_state_payload(vps, id: 'all', state: 'mounted'))

      expect(first.reload.current_state).to eq('mounted')
      expect(first.updated_at).to eq(timestamp)
      expect(second.reload.current_state).to eq('mounted')
      expect(other_mount.reload.current_state).to eq('created')
      expect(other_vps.mounts.count).to eq(2)
    end

    it 'updates only the reported mount id' do
      vps, first, second = create_mount_fixture

      supervisor.send(:update_mount_state, mount_state_payload(vps, id: first.id, state: 'delayed'))

      expect(first.reload.current_state).to eq('delayed')
      expect(first.updated_at).to eq(timestamp)
      expect(second.reload.current_state).to eq('created')
    end
  end
end
