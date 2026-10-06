require 'spec_helper'

RSpec.describe Network do
  around { |example| with_current_context { example.run } }

  it 'permits disabled unowned inventory but rejects owned registration and batch additions atomically' do
    network = SpecSeed.network_v4
    network.update!(enabled: false)
    ip = IpAddress.register(IPAddress.parse('192.0.2.249'), network:, prefix: 32, size: 1)
    expect(ip.user_id).to be_nil
    expect(network.add_ips(1)).not_to be_empty
    before = network.ip_addresses.count
    usage = SpecSeed.user.environment_user_configs.find_by!(environment: SpecSeed.environment).ipv4
    expect do
      IpAddress.register(IPAddress.parse('192.0.2.250'), network:, prefix: 32, size: 1,
                                                         user: SpecSeed.user, environment: SpecSeed.environment)
    end.to raise_error(VpsAdmin::API::Exceptions::IpAddressInvalid, /disabled/)
    expect do
      network.add_ips(1, user: SpecSeed.user, environment: SpecSeed.environment)
    end.to raise_error(VpsAdmin::API::Exceptions::IpAddressInvalid, /disabled/)
    expect(network.ip_addresses.count).to eq(before)
    expect(SpecSeed.user.environment_user_configs.find_by!(environment: SpecSeed.environment).ipv4).to eq(usage)
  end

  it 'retains a competing network reservation when batch lock acquisition fails' do
    network = SpecSeed.network_v4
    reservation = network.acquire_lock(network)
    before = network.ip_addresses.count

    expect { described_class.find(network.id).add_ips(1) }.to raise_error(ResourceLocked)
    expect(ResourceLock.exists?(reservation.id)).to be(true)
    expect(network.ip_addresses.count).to eq(before)
  ensure
    reservation&.release
  end

  it 'uses current family and parsed network metadata when a stale instance adds addresses' do
    network = SpecSeed.network_v4
    network.send(:net_addr)
    described_class.find(network.id).update!(ip_version: 6, address: '2001:db8:abcd::', prefix: 48, split_prefix: 64)

    ip = network.add_ips(1).first
    expect(ip.version).to eq(6)
    expect(ip.to_ip).to be_ipv6
    expect(network.include?(ip)).to be(true)
  end

  it 'rejects direct registration chosen before an incompatible empty-network change' do
    network = SpecSeed.network_v4
    network.send(:net_addr)
    described_class.find(network.id).update!(ip_version: 6, address: '2001:db8:abcd::', prefix: 48, split_prefix: 64)

    expect do
      IpAddress.register(IPAddress.parse('192.0.2.250'), network: network, prefix: 32, size: 1)
    end.to raise_error(ActiveRecord::RecordInvalid, /IP version/)
    expect(network.ip_addresses).to be_empty
  end
end
