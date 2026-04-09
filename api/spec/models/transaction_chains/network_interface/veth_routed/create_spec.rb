# frozen_string_literal: true

require 'spec_helper'

RSpec.describe TransactionChains::NetworkInterface::VethRouted::Create do
  around do |example|
    with_current_context(user: user) { example.run }
  end

  let(:user) { SpecSeed.user }

  it 'creates the interface, confirms it, and calls class hooks' do
    fixture = create_netif_vps_fixture!(
      user: user,
      dataset_name: "veth-create-#{SecureRandom.hex(4)}"
    )
    hook_call = nil

    allow(NetworkInterface).to receive(:create!).and_wrap_original do |orig, *args, **kwargs|
      netif = if kwargs.empty?
                orig.call(*args)
              else
                orig.call(*args, **kwargs)
              end

      allow(netif).to receive(:call_class_hooks_for) do |event, chain, args:|
        hook_call = {
          netif: netif,
          event: event,
          chain_class: chain.class,
          args: args
        }
      end

      netif
    end

    chain, netif = described_class.fire(fixture[:vps], 'eth1')

    expect(netif).to be_persisted
    expect(netif.kind).to eq('veth_routed')
    expect(netif.name).to eq('eth1')
    expect(tx_classes(chain)).to eq([Transactions::NetworkInterface::CreateVethRouted])
    expect(confirmations_for(chain).any? do |row|
      row.class_name == 'NetworkInterface' &&
        row.confirm_type == 'just_create_type' &&
        row.row_pks == { 'id' => netif.id }
    end).to be(true)
    expect(hook_call).to eq(
      netif: netif,
      event: :create,
      chain_class: described_class,
      args: [netif]
    )
  end
end
