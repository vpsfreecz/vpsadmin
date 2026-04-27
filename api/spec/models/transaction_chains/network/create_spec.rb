# frozen_string_literal: true

require 'spec_helper'

RSpec.describe TransactionChains::Network::Create do
  around do |example|
    with_current_context(user: SpecSeed.admin) { example.run }
  end

  def build_network
    Network.new(
      label: "network-create-#{SecureRandom.hex(4)}",
      address: "198.19.#{SecureRandom.random_number(200)}.0",
      prefix: 30,
      ip_version: 4,
      role: :private_access,
      managed: true,
      split_access: :no_access,
      split_prefix: 32,
      purpose: :vps,
      primary_location: SpecSeed.location
    )
  end

  def mark_node_online!(node)
    ensure_available_node_status!(node).tap do |status|
      status.update!(created_at: Time.now.utc, updated_at: Time.now.utc)
    end
  end

  it 'adds IPs, registers the network on online nodes, and confirms creation' do
    node = create_node!(name: "network-register-#{SecureRandom.hex(3)}")
    mark_node_online!(SpecSeed.node)
    mark_node_online!(node)

    network = build_network
    chain, = described_class.fire(network, add_ips: true)
    register_transactions = transactions_for(chain).select do |tx|
      Transaction.for_type(tx.handle) == Transactions::Network::Register
    end

    expect(network).to be_persisted
    expect(network.ip_addresses.count).to eq(2)
    expect(tx_classes(chain).first).to eq(Transactions::Utils::NoOp)
    expect(register_transactions.map(&:node_id)).to contain_exactly(SpecSeed.node.id, node.id)
    expect(
      confirmations_for(chain).find { |row| row.class_name == 'Network' }.confirm_type
    ).to eq('just_create_type')
  end

  it 'skips adding IP addresses when requested' do
    mark_node_online!(SpecSeed.node)

    network = build_network
    chain, = described_class.fire(network, add_ips: false)

    expect(network.ip_addresses).to be_empty
    expect(tx_classes(chain)).not_to include(Transactions::NetworkInterface::AddRoute)
    expect(confirmations_for(chain).select { |row| row.class_name == 'IpAddress' }).to be_empty
  end
end
