# frozen_string_literal: true

require 'spec_helper'

RSpec.describe TransactionChains::NetworkInterface::Destroy do
  around do |example|
    with_current_context(user: user) { example.run }
  end

  let(:user) { SpecSeed.user }

  it 'clears routed addresses before destroying the interface' do
    fixture = create_netif_vps_fixture!(
      user: user,
      dataset_name: "netif-destroy-#{SecureRandom.hex(4)}"
    )
    fixture[:vps].node.location.environment.update!(user_ip_ownership: true)
    create_ip_address!(
      network: SpecSeed.network_v4,
      location: fixture[:pool].node.location,
      network_interface: fixture[:netif],
      addr: '192.0.2.90'
    ).update!(order: 0)

    chain, = described_class.fire(fixture[:netif])

    expect(tx_classes(chain)).to include(
      Transactions::NetworkInterface::DelRoute,
      Transactions::Vps::RemoveVeth
    )
    expect(confirmations_for(chain).any? do |row|
      row.class_name == 'NetworkInterface' &&
        row.confirm_type == 'just_destroy_type' &&
        row.row_pks == { 'id' => fixture[:netif].id }
    end).to be(true)
  end

  it 'can destroy the interface without clearing routes first' do
    fixture = create_netif_vps_fixture!(
      user: user,
      dataset_name: "netif-destroy-no-clear-#{SecureRandom.hex(4)}"
    )

    chain, = described_class.fire(fixture[:netif], clear: false)

    expect(tx_classes(chain)).to eq([Transactions::Vps::RemoveVeth])
    expect(confirmations_for(chain).any? do |row|
      row.class_name == 'NetworkInterface' &&
        row.confirm_type == 'just_destroy_type' &&
        row.row_pks == { 'id' => fixture[:netif].id }
    end).to be(true)
  end

  it 'uses a node-local no-op for venet interfaces' do
    fixture = create_netif_vps_fixture!(
      user: user,
      dataset_name: "venet-destroy-#{SecureRandom.hex(4)}",
      netif_name: 'venet0',
      kind: :venet
    )

    chain, = described_class.fire(fixture[:netif], clear: false)

    expect(tx_classes(chain)).to eq([Transactions::Utils::NoOp])
    expect(confirmations_for(chain).any? do |row|
      row.class_name == 'NetworkInterface' &&
        row.confirm_type == 'just_destroy_type' &&
        row.row_pks == { 'id' => fixture[:netif].id }
    end).to be(true)
  end
end
