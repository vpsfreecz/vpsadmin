# frozen_string_literal: true

require 'spec_helper'

RSpec.describe TransactionChains::Network::AddIps do
  around do |example|
    with_current_context(user: SpecSeed.admin) { example.run }
  end

  it 'creates requested addresses and confirms them with one NoOp carrier' do
    ensure_available_node_status!(SpecSeed.node)
    network = Network.create!(
      label: "add-ips-#{SecureRandom.hex(4)}",
      address: "198.18.#{SecureRandom.random_number(200)}.0",
      prefix: 29,
      ip_version: 4,
      role: :private_access,
      managed: true,
      split_access: :no_access,
      split_prefix: 32,
      purpose: :vps,
      primary_location: SpecSeed.location
    )

    chain, = described_class.fire(network, 3)

    expect(tx_classes(chain)).to eq([Transactions::Utils::NoOp])
    expect(network.ip_addresses.count).to eq(3)
    expect(
      confirmations_for(chain).select { |row| row.class_name == 'IpAddress' }.map(&:confirm_type)
    ).to eq(%w[just_create_type just_create_type just_create_type])
  end
end
