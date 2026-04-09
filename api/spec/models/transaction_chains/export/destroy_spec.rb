# frozen_string_literal: true

require 'spec_helper'

RSpec.describe TransactionChains::Export::Destroy do
  around do |example|
    with_current_context(user: user) { example.run }
  end

  let(:user) { SpecSeed.user }

  def create_destroy_fixture(snapshot: false)
    pool = create_pool!(node: SpecSeed.node, role: :primary)
    dataset, dip = create_dataset_with_pool!(
      user: user,
      pool: pool,
      name: "export-destroy-#{SecureRandom.hex(4)}"
    )
    export_network = create_private_network!(location: pool.node.location)
    create_ipv4_address_in_network!(network: export_network, location: pool.node.location)
    export_obj =
      if snapshot
        _snapshot_record, sip = create_snapshot!(dataset: dataset, dip: dip, name: 'snap-1')
        clone = SnapshotInPoolClone.create!(
          snapshot_in_pool: sip,
          user_namespace_map: create_user_namespace_map!(user: user),
          name: "#{sip.snapshot_id}-export.snapshot",
          state: :active
        )
        export, = create_export_for_dataset!(dataset_in_pool: dip, enabled: true)
        export.update!(
          snapshot_in_pool_clone: clone,
          snapshot_in_pool_clone_n: clone.id
        )
        export
      else
        create_export_for_dataset!(dataset_in_pool: dip, enabled: true).first
      end

    host = ExportHost.create!(
      export: export_obj,
      ip_address: create_ip_address!(network: SpecSeed.network_v4, location: pool.node.location),
      rw: true,
      sync: true,
      subtree_check: false,
      root_squash: false
    )
    [export_obj.reload, host]
  end

  it 'disables before destroying and confirms associated cleanup' do
    export, host = create_destroy_fixture

    chain, = described_class.fire(export)

    expect(tx_classes(chain)).to eq(
      [
        Transactions::Export::Disable,
        Transactions::Export::Destroy
      ]
    )
    expect(export.reload.confirmed).to eq(:confirm_destroy)
    expect(confirmations_for(chain).any? do |row|
      row.class_name == 'Export' &&
        row.confirm_type == 'destroy_type' &&
        row.row_pks == { 'id' => export.id }
    end).to be(true)
    expect(confirmations_for(chain).any? do |row|
      row.class_name == 'NetworkInterface' &&
        row.confirm_type == 'just_destroy_type' &&
        row.row_pks == { 'id' => export.network_interface.id }
    end).to be(true)
    expect(confirmations_for(chain).any? do |row|
      row.class_name == 'ExportHost' &&
        row.confirm_type == 'just_destroy_type' &&
        row.row_pks == { 'id' => host.id }
    end).to be(true)
    expect(confirmations_for(chain).any? do |row|
      row.class_name == 'IpAddress' &&
        row.row_pks == { 'id' => export.ip_address.id } &&
        row.attr_changes == { 'network_interface_id' => nil }
    end).to be(true)
  end

  it 'deactivates snapshot clones when destroying snapshot exports' do
    export, = create_destroy_fixture(snapshot: true)

    chain, = described_class.fire(export)

    expect(tx_classes(chain)).to include(
      Transactions::Export::Disable,
      Transactions::Export::Destroy,
      Transactions::Storage::DeactivateSnapshotClone
    )
    clone_confirmation = confirmations_for(chain).find do |row|
      row.class_name == 'SnapshotInPoolClone'
    end
    expect(clone_confirmation.attr_changes).to eq(
      'state' => SnapshotInPoolClone.states.fetch('inactive')
    )
  end
end
