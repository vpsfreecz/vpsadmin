# frozen_string_literal: true

require 'spec_helper'

RSpec.describe VpsAdmin::Supervisor::Node::VpsSshHostKeys do
  let(:node) { SpecSeed.node }
  let(:supervisor) { described_class.new(nil, node) }
  let(:timestamp) { Time.utc(2026, 4, 5, 22, 0, 0) }
  let(:old_time) { Time.utc(2026, 4, 5, 21, 0, 0) }

  def keys_payload(vps, keys)
    {
      'vps_id' => vps.id,
      'time' => timestamp.to_i,
      'keys' => keys
    }
  end

  describe '#update_vps_keys' do
    it 'updates existing keys, creates new keys, and removes missing keys' do
      vps = build_standalone_vps_fixture(node:).fetch(:vps)
      rsa = VpsSshHostKey.create!(
        vps:,
        algorithm: 'ssh-rsa',
        bits: 2048,
        fingerprint: 'old-rsa',
        created_at: old_time,
        updated_at: old_time
      )
      removed = VpsSshHostKey.create!(
        vps:,
        algorithm: 'ssh-ed25519',
        bits: 256,
        fingerprint: 'old-ed25519',
        created_at: old_time,
        updated_at: old_time
      )

      supervisor.send(
        :update_vps_keys,
        keys_payload(
          vps,
          [
            { 'algorithm' => 'ssh-rsa', 'bits' => 4096, 'fingerprint' => 'new-rsa' },
            { 'algorithm' => 'ecdsa-sha2-nistp256', 'bits' => 256, 'fingerprint' => 'new-ecdsa' }
          ]
        )
      )

      expect(rsa.reload.bits).to eq(4096)
      expect(rsa.fingerprint).to eq('new-rsa')
      expect(rsa.created_at).to eq(old_time)
      expect(rsa.updated_at).to eq(timestamp)
      expect(VpsSshHostKey.where(id: removed.id)).not_to exist

      created = VpsSshHostKey.find_by!(vps:, algorithm: 'ecdsa-sha2-nistp256')
      expect(created.bits).to eq(256)
      expect(created.fingerprint).to eq('new-ecdsa')
      expect(created.created_at).to eq(timestamp)
      expect(created.updated_at).to eq(timestamp)
    end

    it 'ignores unknown VPS ids and VPSes on other nodes' do
      other_vps = build_standalone_vps_fixture(node: SpecSeed.other_node).fetch(:vps)
      existing = VpsSshHostKey.create!(
        vps: other_vps,
        algorithm: 'ssh-rsa',
        bits: 2048,
        fingerprint: 'keep',
        created_at: old_time,
        updated_at: old_time
      )

      supervisor.send(
        :update_vps_keys,
        keys_payload(
          other_vps,
          [
            { 'algorithm' => 'ssh-rsa', 'bits' => 4096, 'fingerprint' => 'ignore' },
            { 'algorithm' => 'ssh-ed25519', 'bits' => 256, 'fingerprint' => 'ignore' }
          ]
        )
      )

      expect(existing.reload.bits).to eq(2048)
      expect(existing.fingerprint).to eq('keep')
      expect(VpsSshHostKey.where(vps: other_vps).count).to eq(1)

      unknown_id = Vps.maximum(:id).to_i + 10_000
      supervisor.send(
        :update_vps_keys,
        {
          'vps_id' => unknown_id,
          'time' => timestamp.to_i,
          'keys' => [
            { 'algorithm' => 'ssh-rsa', 'bits' => 2048, 'fingerprint' => 'ignore' }
          ]
        }
      )

      expect(VpsSshHostKey.where(vps_id: unknown_id)).not_to exist
    end
  end
end
