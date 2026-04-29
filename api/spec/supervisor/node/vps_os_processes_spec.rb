# frozen_string_literal: true

require 'spec_helper'

RSpec.describe VpsAdmin::Supervisor::Node::VpsOsProcesses do
  let(:node) { SpecSeed.node }
  let(:supervisor) { described_class.new(nil, node) }
  let(:timestamp) { Time.utc(2026, 4, 5, 21, 0, 0) }
  let(:old_time) { Time.utc(2026, 4, 5, 20, 0, 0) }

  describe '#update_vps_processes' do
    it 'replaces the latest process-state snapshot for VPSes on the current node' do
      vps = build_standalone_vps_fixture(node:).fetch(:vps)
      VpsOsProcess.create!(vps:, state: 'R', count: 1, created_at: old_time, updated_at: old_time)
      VpsOsProcess.create!(vps:, state: 'S', count: 3, created_at: old_time, updated_at: old_time)

      supervisor.send(
        :update_vps_processes,
        {
          'time' => timestamp.to_i,
          'vps_processes' => [
            {
              'vps_id' => vps.id,
              'processes' => { 'R' => 2, 'Z' => 1 }
            }
          ]
        }
      )

      running = VpsOsProcess.find_by!(vps:, state: 'R')
      zombie = VpsOsProcess.find_by!(vps:, state: 'Z')
      expect(running.count).to eq(2)
      expect(running.created_at).to eq(old_time)
      expect(running.updated_at).to eq(timestamp)
      expect(zombie.count).to eq(1)
      expect(zombie.created_at).to eq(timestamp)
      expect(VpsOsProcess.where(vps:, state: 'S')).not_to exist
    end

    it 'ignores unknown VPS ids and VPSes on other nodes' do
      other_vps = build_standalone_vps_fixture(node: SpecSeed.other_node).fetch(:vps)
      VpsOsProcess.create!(
        vps: other_vps,
        state: 'S',
        count: 1,
        created_at: old_time,
        updated_at: old_time
      )
      unknown_id = Vps.maximum(:id).to_i + 10_000

      supervisor.send(
        :update_vps_processes,
        {
          'time' => timestamp.to_i,
          'vps_processes' => [
            {
              'vps_id' => other_vps.id,
              'processes' => { 'S' => 9, 'Z' => 2 }
            },
            {
              'vps_id' => unknown_id,
              'processes' => { 'R' => 1 }
            }
          ]
        }
      )

      expect(VpsOsProcess.find_by!(vps: other_vps, state: 'S').count).to eq(1)
      expect(VpsOsProcess.where(vps: other_vps, state: 'Z')).not_to exist
      expect(VpsOsProcess.where(vps_id: unknown_id)).not_to exist
    end
  end
end
