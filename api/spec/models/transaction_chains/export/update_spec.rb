# frozen_string_literal: true

require 'spec_helper'

RSpec.describe TransactionChains::Export::Update do
  around do |example|
    with_current_context(user: user) { example.run }
  end

  let(:user) { SpecSeed.user }

  def create_update_fixture(enabled: true)
    pool = create_pool!(node: SpecSeed.node, role: :primary)
    ensure_available_node_status!(pool.node)
    dataset, dip = create_dataset_with_pool!(
      user: user,
      pool: pool,
      name: "export-update-#{SecureRandom.hex(4)}"
    )
    export_network = create_private_network!(location: pool.node.location)
    create_ipv4_address_in_network!(network: export_network, location: pool.node.location)
    export, = create_export_for_dataset!(dataset_in_pool: dip, enabled: enabled)

    vps = create_vps_for_dataset!(user: user, node: pool.node, dataset_in_pool: dip)
    netif = create_network_interface!(vps, name: 'eth0')
    create_ip_address!(network_interface: netif)

    export.reload
  end

  it 'disables before runtime updates when switching an active export off' do
    export = create_update_fixture(enabled: true)

    chain, = described_class.fire(export, enabled: false, threads: 12)

    expect(tx_classes(chain)).to include(
      Transactions::Export::Disable,
      Transactions::Export::Set
    )
    expect(
      tx_classes(chain).index(Transactions::Export::Disable)
    ).to be < tx_classes(chain).index(Transactions::Export::Set)
    expect(tx_payload(chain, Transactions::Export::Set)).to include(
      'new' => include('threads' => 12),
      'original' => include('threads' => export.threads)
    )
    confirmation = confirmations_for(chain).find do |row|
      row.class_name == 'Export' && row.row_pks == { 'id' => export.id }
    end
    expect(confirmation.attr_changes).to eq('enabled' => 0)
  end

  it 'persists db changes, creates missing hosts, and enables last' do
    export = create_update_fixture(enabled: false)

    chain, = described_class.fire(export, all_vps: true, threads: 20, enabled: true)

    expect(tx_classes(chain)).to eq(
      [
        Transactions::Export::Set,
        Transactions::Utils::NoOp,
        Transactions::Export::AddHosts,
        Transactions::Export::Enable
      ]
    )
    expect(export.reload.export_hosts.count).to eq(1)
    db_confirmation = confirmations_for(chain).find do |row|
      row.class_name == 'Export' &&
        row.confirm_type == 'edit_after_type' &&
        row.attr_changes.is_a?(Hash) &&
        row.attr_changes['all_vps'] == 1
    end
    expect(db_confirmation).to be_present
    expect(db_confirmation.attr_changes).to include('threads' => 20)
  end

  it 'uses a NoOp confirmation for db-only changes' do
    export = create_update_fixture(enabled: true)

    chain, = use_chain_in_root!(described_class, args: [export, { rw: false, sync: false }])

    expect(tx_classes(chain)).to eq([Transactions::Utils::NoOp])
    expect(confirmations_for(chain).find do |row|
      row.class_name == 'Export' &&
        row.attr_changes.is_a?(Hash) &&
        row.attr_changes['rw'] == 0 &&
        row.attr_changes['sync'] == 0
    end).to be_present
  end

  it 'returns an empty chain when nothing changes' do
    export = create_update_fixture(enabled: true)

    chain, returned = use_chain_in_root!(described_class, args: [export, {}])

    expect(returned.id).to eq(export.id)
    expect(chain.transactions).to be_empty
  end
end
