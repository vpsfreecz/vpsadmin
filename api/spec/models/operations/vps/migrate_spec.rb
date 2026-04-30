# frozen_string_literal: true

require 'spec_helper'

RSpec.describe VpsAdmin::API::Operations::Vps::Migrate do
  around do |example|
    with_current_context(user: SpecSeed.user) { example.run }
  end

  it 'maps API option names to transaction-chain option names' do
    vps = build_standalone_vps_fixture.fetch(:vps)
    node = create_node!(location: SpecSeed.location, role: :node)
    chain = instance_double(TransactionChain)
    chain_class = class_double(TransactionChains::Vps::Migrate::OsToOs)
    maintenance_window = instance_double(VpsMaintenanceWindow)
    opts = {
      node: node,
      replace_ip_addresses: true,
      transfer_ip_addresses: false,
      swap: 'move',
      maintenance_window: maintenance_window,
      finish_weekday: 2,
      finish_minutes: 180,
      send_mail: true,
      reason: 'maintenance',
      cleanup_data: false,
      no_start: true,
      skip_start: false
    }

    allow(TransactionChains::Vps::Migrate).to receive(:chain_for)
      .with(vps, node)
      .and_return(chain_class)
    allow(chain_class).to receive(:fire).and_return([chain, vps])

    expect(described_class.run(vps, opts)).to eq(chain)
    expect(chain_class).to have_received(:fire).with(
      vps,
      node,
      replace_ips: true,
      transfer_ips: false,
      swap: :move,
      maintenance_window: maintenance_window,
      finish_weekday: 2,
      finish_minutes: 180,
      send_mail: true,
      reason: 'maintenance',
      cleanup_data: false,
      no_start: true,
      skip_start: false
    )
  end
end
