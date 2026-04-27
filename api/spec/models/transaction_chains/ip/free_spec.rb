# frozen_string_literal: true

require 'spec_helper'

RSpec.describe TransactionChains::Ip::Free do
  around do |example|
    with_current_context(user: user) { example.run }
  end

  let(:user) { SpecSeed.user }
  let(:resource) { ClusterResource.find_by!(name: 'ipv4_private') }

  def create_owned_ip_fixture(with_transfer: false)
    network = create_private_network!(
      location: SpecSeed.location,
      purpose: :vps
    )
    ip = create_ipv4_address_in_network!(
      network: network,
      location: SpecSeed.location,
      user: user
    )
    ip.update!(charged_environment: SpecSeed.environment)
    host_ip = ip.host_ip_addresses.take!
    host_ip.update!(user_created: true)

    if with_transfer
      dns_zone = create_dns_zone!(source: :internal_source)
      dns_server = create_dns_server!(node: SpecSeed.node)
      create_dns_server_zone!(
        dns_zone: dns_zone,
        dns_server: dns_server,
        zone_type: :primary_type
      )
      create_dns_zone_transfer!(
        dns_zone: dns_zone,
        host_ip_address: host_ip,
        peer_type: :secondary_type
      )
    end

    [ip, host_ip]
  end

  it 'clears ownership and deletes user-created host addresses through confirmations' do
    ensure_available_node_status!(SpecSeed.node)
    ip, host_ip = create_owned_ip_fixture
    user_env = user.environment_user_configs.find_by!(environment: SpecSeed.environment)

    chain, = use_chain_method_in_root!(
      described_class,
      method: :free_from_environment_user_config,
      args: [resource, user_env]
    )

    expect(tx_classes(chain)).to eq(
      [
        Transactions::Utils::NoOp,
        Transactions::Utils::NoOp
      ]
    )
    expect(
      confirmations_for(chain).find { |row| row.class_name == 'IpAddress' && row.row_pks == { 'id' => ip.id } }
        .attr_changes
    ).to eq('user_id' => nil, 'charged_environment_id' => nil)
    expect(
      confirmations_for(chain).find do |row|
        row.class_name == 'HostIpAddress' && row.row_pks == { 'id' => host_ip.id }
      end.confirm_type
    ).to eq('just_destroy_type')
  end

  it 'destroys DNS zone transfers before freeing IP ownership' do
    ip, = create_owned_ip_fixture(with_transfer: true)
    user_env = user.environment_user_configs.find_by!(environment: SpecSeed.environment)

    chain, = use_chain_method_in_root!(
      described_class,
      method: :free_from_environment_user_config,
      args: [resource, user_env]
    )

    expect(tx_classes(chain).first(3)).to eq(
      [
        Transactions::DnsServerZone::RemoveServers,
        Transactions::DnsServer::Reload,
        Transactions::Utils::NoOp
      ]
    )
    ip_confirmation = confirmations_for(chain).find do |row|
      row.class_name == 'IpAddress' && row.row_pks == { 'id' => ip.id }
    end
    transfer_confirmation = confirmations_for(chain).find { |row| row.class_name == 'DnsZoneTransfer' }

    expect(transfer_confirmation.confirm_type).to eq('destroy_type')
    expect(ip_confirmation.attr_changes).to eq('user_id' => nil, 'charged_environment_id' => nil)
  end
end
