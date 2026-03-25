# frozen_string_literal: true

require 'spec_helper'

RSpec.describe TransactionChains::NetworkInterface::DelRoute do
  around do |example|
    with_current_context do
      example.run
    end
  end

  let(:user) { SpecSeed.user }

  it 'does not reallocate cluster resources when no IPs are being removed' do
    pool = create_pool!(node: SpecSeed.node, role: :primary)
    _dataset, dip = create_dataset_with_pool!(
      user: user,
      pool: pool,
      name: "del-route-#{SecureRandom.hex(4)}"
    )
    vps = create_vps_for_dataset!(user: user, node: pool.node, dataset_in_pool: dip)
    netif = NetworkInterface.create!(
      vps: vps,
      name: 'eth0',
      kind: :veth_routed,
      enable: true,
      max_tx: 0,
      max_rx: 0
    )
    ip = IpAddress.create!(
      network: SpecSeed.network_v4,
      ip_addr: '192.0.2.50',
      prefix: SpecSeed.network_v4.split_prefix,
      size: 1,
      network_interface: netif
    )
    HostIpAddress.create!(
      ip_address: ip,
      ip_addr: '192.0.2.50',
      auto_add: true,
      order: nil
    )
    user_env = vps.user.environment_user_configs.find_by!(
      environment: vps.node.location.environment
    )
    user_env.reallocate_resource!(
      :ipv4,
      user_env.ipv4 + 1,
      user: user,
      save: true,
      confirmed: ClusterResourceUse.confirmed(:confirmed)
    )
    configs = vps.user.environment_user_configs

    allow(vps.user).to receive(:environment_user_configs).and_return(configs)
    allow(configs).to receive(:find_by!)
      .with(environment: vps.node.location.environment)
      .and_return(user_env)
    allow(user_env).to receive(:reallocate_resource!)
      .and_wrap_original do |orig, resource, *args, **kwargs|
        raise 'unexpected resource reallocation' \
          if %i[ipv4_private ipv6].include?(resource.to_sym)

        orig.call(resource, *args, **kwargs)
      end

    expect { described_class.fire(netif, [ip]) }.not_to raise_error
  end
end
