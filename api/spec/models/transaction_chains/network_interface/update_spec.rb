# frozen_string_literal: true

require 'spec_helper'

RSpec.describe TransactionChains::NetworkInterface::Update do
  around do |example|
    with_current_context(user: user) { example.run }
  end

  let(:user) { SpecSeed.user }

  it 'renames first, then updates the shaper, and writes a rename log' do
    fixture = create_netif_vps_fixture!(
      user: user,
      dataset_name: "netif-update-#{SecureRandom.hex(4)}"
    )

    chain, updated = described_class.fire(
      fixture[:netif],
      name: 'lan0',
      max_tx: 1000,
      max_rx: 2000
    )

    expect(updated.name).to eq('lan0')
    expect(tx_classes(chain)).to eq(
      [
        Transactions::NetworkInterface::Rename,
        Transactions::NetworkInterface::SetShaper
      ]
    )
    expect(tx_payload(chain, Transactions::NetworkInterface::SetShaper)).to include(
      'veth_name' => 'lan0',
      'max_tx' => { 'new' => 1000, 'original' => 0 },
      'max_rx' => { 'new' => 2000, 'original' => 0 }
    )
    expect(confirmations_for(chain).any? do |row|
      row.class_name == 'NetworkInterface' &&
        row.attr_changes.is_a?(Hash) &&
        row.attr_changes['name'] == 'lan0'
    end).to be(true)
    expect(
      fixture[:vps].object_histories.where(event_type: 'netif_rename').pluck(:event_data)
    ).to include(
      {
        'id' => fixture[:netif].id,
        'name' => 'eth0',
        'new_name' => 'lan0'
      }
    )
  end

  it 'emits enable and disable transactions with log rows' do
    disabled_fixture = create_netif_vps_fixture!(
      user: user,
      dataset_name: "netif-enable-#{SecureRandom.hex(4)}",
      enable: false
    )

    enable_chain, = described_class.fire(disabled_fixture[:netif], enable: true)

    expect(tx_classes(enable_chain)).to eq([Transactions::NetworkInterface::Enable])
    expect(
      disabled_fixture[:vps].object_histories.where(event_type: 'netif_enable').pluck(:event_data)
    ).to include(
      {
        'id' => disabled_fixture[:netif].id,
        'name' => disabled_fixture[:netif].name,
        'enable' => true
      }
    )

    enabled_fixture = create_netif_vps_fixture!(
      user: user,
      dataset_name: "netif-disable-#{SecureRandom.hex(4)}",
      netif_name: 'eth1'
    )

    disable_chain, = described_class.fire(enabled_fixture[:netif], enable: false)

    expect(tx_classes(disable_chain)).to eq([Transactions::NetworkInterface::Disable])
    expect(
      enabled_fixture[:vps].object_histories.where(event_type: 'netif_enable').pluck(:event_data)
    ).to include(
      {
        'id' => enabled_fixture[:netif].id,
        'name' => enabled_fixture[:netif].name,
        'enable' => false
      }
    )
  end

  it 'returns an empty chain when the interface stays unchanged' do
    fixture = create_netif_vps_fixture!(
      user: user,
      dataset_name: "netif-noop-#{SecureRandom.hex(4)}"
    )

    chain, returned = use_chain_in_root!(
      described_class,
      args: [fixture[:netif], { name: fixture[:netif].name, enable: fixture[:netif].enable }]
    )

    expect(returned.id).to eq(fixture[:netif].id)
    expect(chain.transactions).to be_empty
  end
end
