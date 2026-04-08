# frozen_string_literal: true

require 'spec_helper'

RSpec.describe TransactionChains::Vps::DestroyMount do
  around do |example|
    unlock_transaction_signer!
    with_current_context(user: user) { example.run }
  end

  let(:user) { SpecSeed.user }

  it 'delegates regular mounts to UmountDataset and marks the mount for destruction' do
    fixture = build_standalone_vps_fixture(user: user, hostname: 'destroy-mount')
    _subdataset, sub_dip = create_vps_subdataset!(
      user: user,
      pool: fixture.fetch(:pool),
      parent: fixture.fetch(:dataset)
    )
    mount = create_mount_record!(vps: fixture.fetch(:vps), dataset_in_pool: sub_dip, dst: '/mnt/data')

    chain, = described_class.fire(mount)

    expect(tx_classes(chain)).to include(
      Transactions::Vps::Mounts,
      Transactions::Vps::Umount,
      Transactions::Utils::NoOp
    )
    expect(mount.reload.confirmed).to eq(:confirm_destroy)
    expect(confirmations_for(chain).any? do |row|
      row.class_name == 'Mount' &&
        row.row_pks == { 'id' => mount.id } &&
        row.confirm_type == 'destroy_type'
    end).to be(true)
  end

  it 'raises for snapshot mounts' do
    fixture = build_standalone_vps_fixture(user: user, hostname: 'destroy-snapshot-mount-only')
    snapshot, snapshot_in_pool = create_snapshot!(
      dataset: fixture.fetch(:dataset),
      dip: fixture.fetch(:dataset_in_pool),
      name: 'mount-snapshot'
    )
    mount = create_snapshot_mount_record!(
      vps: fixture.fetch(:vps),
      snapshot_in_pool: snapshot_in_pool
    )

    expect do
      described_class.fire(mount)
    end.to raise_error(RuntimeError, 'snapshot mounts are not supported')

    expect(snapshot).to be_present
  end
end
