# frozen_string_literal: true

require 'spec_helper'

RSpec.describe VpsAdmin::Supervisor::Node::ExportMounts do
  let(:node) { SpecSeed.node }
  let(:supervisor) { described_class.new(nil, node) }
  let(:timestamp) { Time.utc(2026, 4, 5, 18, 0, 0) }

  def export_payload(vps, export, host_ip, mounts)
    {
      'vps_id' => vps.id,
      'time' => timestamp.to_i,
      'mounts' => mounts.map do |mount|
        {
          'server_address' => host_ip.host_ip_addresses.first.ip_addr,
          'server_path' => export.path,
          'mountpoint' => mount.fetch(:mountpoint),
          'nfs_version' => mount.fetch(:nfs_version)
        }
      end
    }
  end

  describe '#update_export_mounts' do
    it 'creates mounts that are present in the payload' do
      fixture = build_standalone_vps_fixture(node:)
      vps = fixture.fetch(:vps)
      export, _netif, host_ip = create_export_for_dataset!(dataset_in_pool: fixture.fetch(:dataset_in_pool))

      supervisor.send(
        :update_export_mounts,
        export_payload(vps, export, host_ip, [{ mountpoint: '/mnt/export', nfs_version: '4.2' }])
      )

      mount = ExportMount.find_by!(vps:, export:)
      expect(mount.mountpoint).to eq('/mnt/export')
      expect(mount.nfs_version).to eq('4.2')
    end

    it 'updates existing mounts and removes stale mounts for the reported VPS' do
      fixture = build_standalone_vps_fixture(node:)
      other_fixture = build_standalone_vps_fixture(node:)
      vps = fixture.fetch(:vps)
      export, _netif, host_ip = create_export_for_dataset!(dataset_in_pool: fixture.fetch(:dataset_in_pool))
      existing = ExportMount.create!(vps:, export:, mountpoint: '/mnt/export', nfs_version: '3')
      stale = ExportMount.create!(vps:, export:, mountpoint: '/mnt/stale', nfs_version: '4')
      unrelated = ExportMount.create!(
        vps: other_fixture.fetch(:vps),
        export:,
        mountpoint: '/mnt/keep',
        nfs_version: '4'
      )

      supervisor.send(
        :update_export_mounts,
        export_payload(vps, export, host_ip, [{ mountpoint: '/mnt/export', nfs_version: '4.2' }])
      )

      expect(existing.reload.nfs_version).to eq('4.2')
      expect(existing.updated_at).to eq(timestamp)
      expect(ExportMount.where(id: stale.id)).not_to exist
      expect(ExportMount.where(id: unrelated.id)).to exist
    end

    it 'ignores mounts for unknown exports' do
      fixture = build_standalone_vps_fixture(node:)
      vps = fixture.fetch(:vps)
      export, _netif, host_ip = create_export_for_dataset!(dataset_in_pool: fixture.fetch(:dataset_in_pool))
      payload = export_payload(vps, export, host_ip, [{ mountpoint: '/mnt/missing', nfs_version: '4' }])
      payload.fetch('mounts').first['server_path'] = '/missing'

      supervisor.send(:update_export_mounts, payload)

      expect(ExportMount.where(vps:)).to be_empty
    end
  end
end
