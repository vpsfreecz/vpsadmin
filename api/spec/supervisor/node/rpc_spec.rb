# frozen_string_literal: true

require 'securerandom'
require 'spec_helper'

RSpec.describe 'VpsAdmin::Supervisor::Node::Rpc::Handler' do
  let(:node) { SpecSeed.node }
  let(:user) { SpecSeed.user }
  let(:handler) { VpsAdmin::Supervisor::Node::Rpc::Handler.new(node) }

  before do
    SpecSeed.user
    SpecSeed.node
    SpecSeed.pool
    SpecSeed.os_template
    SpecSeed.dns_resolver
    SpecSeed.network_v4
  end

  def create_vps!(dataset_in_pool:, user_namespace_map: create_user_namespace_map!(user: user))
    Vps.create!(
      user: user,
      node: node,
      hostname: "spec-vps-#{SecureRandom.hex(4)}",
      os_template: SpecSeed.os_template,
      dns_resolver: SpecSeed.dns_resolver,
      dataset_in_pool: dataset_in_pool,
      user_namespace_map: user_namespace_map,
      object_state: :active,
      confirmed: :confirmed
    )
  end

  def create_ip!(addr:, network:, user: nil, netif: nil)
    ip = IpAddress.create!(
      ip_addr: addr,
      prefix: network.split_prefix,
      size: 1,
      network: network,
      user: user,
      network_interface: netif
    )

    HostIpAddress.create!(
      ip_address: ip,
      ip_addr: addr,
      auto_add: true,
      order: nil
    )

    ip
  end

  def create_export!(dataset_in_pool:, with_ip: true, ip_addr: '192.0.2.11')
    export = nil

    Uuid.generate_for_new_record! do |uuid|
      export = Export.new(
        dataset_in_pool: dataset_in_pool,
        snapshot_in_pool_clone: nil,
        snapshot_in_pool_clone_n: 0,
        user: user,
        all_vps: false,
        path: "/export/#{dataset_in_pool.dataset.full_name}",
        rw: true,
        sync: true,
        subtree_check: false,
        root_squash: false,
        threads: 8,
        enabled: true,
        object_state: :active,
        confirmed: :confirmed
      )
      export.uuid = uuid
      export.save!
      export
    end

    return export unless with_ip

    netif = NetworkInterface.create!(export: export, kind: :veth_routed, name: 'eth0')
    create_ip!(addr: ip_addr, network: SpecSeed.network_v4, netif: netif)
    export.reload
  end

  describe '#list_vps_status_check' do
    it 'skips vpses with a missing dataset_in_pool' do
      _, valid_dip = create_dataset_with_pool!(
        user: user,
        pool: SpecSeed.pool,
        name: "status-good-#{SecureRandom.hex(4)}"
      )
      _, invalid_dip = create_dataset_with_pool!(
        user: user,
        pool: SpecSeed.pool,
        name: "status-bad-#{SecureRandom.hex(4)}"
      )

      valid_vps = create_vps!(dataset_in_pool: valid_dip)
      invalid_vps = create_vps!(dataset_in_pool: invalid_dip)
      invalid_vps.update_column(:dataset_in_pool_id, nil)
      result = nil

      expect do
        result = handler.list_vps_status_check
      end.not_to raise_error

      expect(result).to contain_exactly(
        {
          id: valid_vps.id,
          read_hostname: false,
          pool_fs: SpecSeed.pool.filesystem
        }
      )
    end
  end

  describe '#list_vps_user_namespace_maps' do
    it 'skips vpses with a missing user_namespace_map' do
      _, valid_dip = create_dataset_with_pool!(
        user: user,
        pool: SpecSeed.pool,
        name: "userns-good-#{SecureRandom.hex(4)}"
      )
      _, invalid_dip = create_dataset_with_pool!(
        user: user,
        pool: SpecSeed.pool,
        name: "userns-bad-#{SecureRandom.hex(4)}"
      )

      valid_map = create_user_namespace_map!(user: user)
      valid_vps = create_vps!(dataset_in_pool: valid_dip, user_namespace_map: valid_map)
      invalid_vps = create_vps!(dataset_in_pool: invalid_dip)
      invalid_vps.update_column(:user_namespace_map_id, nil)
      result = nil

      expect do
        result = handler.list_vps_user_namespace_maps(SpecSeed.pool.id, limit: 10)
      end.not_to raise_error

      expect(result).to contain_exactly(
        {
          vps_id: valid_vps.id,
          map_name: valid_map.id.to_s,
          uidmap: [],
          gidmap: []
        }
      )
    end
  end

  describe '#list_exports' do
    it 'skips exports with incomplete related rows' do
      _, valid_dip = create_dataset_with_pool!(
        user: user,
        pool: SpecSeed.pool,
        name: "export-good-#{SecureRandom.hex(4)}"
      )
      _, invalid_dip = create_dataset_with_pool!(
        user: user,
        pool: SpecSeed.pool,
        name: "export-bad-#{SecureRandom.hex(4)}"
      )

      valid_export = create_export!(dataset_in_pool: valid_dip, with_ip: true)
      create_export!(dataset_in_pool: invalid_dip, with_ip: false)
      result = nil

      expect do
        result = handler.list_exports(limit: 10)
      end.not_to raise_error

      expect(result).to contain_exactly(
        {
          id: valid_export.id,
          pool_fs: SpecSeed.pool.filesystem,
          dataset_name: valid_dip.dataset.full_name,
          clone_name: nil,
          path: valid_export.path,
          threads: valid_export.threads,
          enabled: valid_export.enabled,
          ip_address: '192.0.2.11',
          hosts: []
        }
      )
    end
  end
end
