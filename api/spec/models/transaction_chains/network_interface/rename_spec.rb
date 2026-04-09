# frozen_string_literal: true

require 'spec_helper'

RSpec.describe TransactionChains::NetworkInterface::Rename do
  around do |example|
    with_current_context(user: user) { example.run }
  end

  let(:user) { SpecSeed.user }

  it 'renames the interface and writes a rename log row' do
    fixture = create_netif_vps_fixture!(
      user: user,
      dataset_name: "netif-rename-#{SecureRandom.hex(4)}"
    )

    chain, = described_class.fire(fixture[:netif], 'wan0')

    expect(tx_classes(chain)).to eq([Transactions::NetworkInterface::Rename])
    expect(tx_payload(chain, Transactions::NetworkInterface::Rename)).to include(
      'name' => 'wan0',
      'original' => 'eth0',
      'netif_id' => fixture[:netif].id
    )
    expect(confirmations_for(chain).any? do |row|
      row.class_name == 'NetworkInterface' &&
        row.attr_changes == { 'name' => 'wan0' }
    end).to be(true)
    expect(
      fixture[:vps].object_histories.where(event_type: 'netif_rename').pluck(:event_data)
    ).to include(
      {
        'id' => fixture[:netif].id,
        'name' => 'eth0',
        'new_name' => 'wan0'
      }
    )
  end
end
