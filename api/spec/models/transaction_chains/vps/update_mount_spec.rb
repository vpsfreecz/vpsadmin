# frozen_string_literal: true

require 'spec_helper'

RSpec.describe TransactionChains::Vps::UpdateMount do
  around do |example|
    unlock_transaction_signer!
    with_current_context(user: user) { example.run }
  end

  let(:user) { SpecSeed.user }

  def create_mount_fixture(enabled: true, master_enabled: true, on_start_fail: :mount_later)
    fixture = build_standalone_vps_fixture(user: user, hostname: "update-mount-#{SecureRandom.hex(4)}")
    _subdataset, sub_dip = create_vps_subdataset!(
      user: user,
      pool: fixture.fetch(:pool),
      parent: fixture.fetch(:dataset)
    )

    mount = create_mount_record!(
      vps: fixture.fetch(:vps),
      dataset_in_pool: sub_dip,
      dst: '/mnt/data',
      enabled: enabled,
      master_enabled: master_enabled,
      on_start_fail: on_start_fail
    )

    fixture.merge(mount: mount)
  end

  it 'enables a disabled mount through Mounts and Mount and records edit_before for enabled' do
    fixture = create_mount_fixture(enabled: false)
    mount = fixture.fetch(:mount)

    chain, = described_class.fire(mount, enabled: true)
    confirmation = confirmations_for(chain).find do |row|
      row.class_name == 'Mount' && row.row_pks == { 'id' => mount.id } && row.attr_changes == { 'enabled' => 0 }
    end

    expect(tx_classes(chain)).to include(
      Transactions::Vps::Mounts,
      Transactions::Vps::Mount,
      Transactions::Utils::NoOp
    )
    expect(tx_classes(chain)).not_to include(Transactions::Vps::Umount)
    expect(mount.reload.enabled).to be(true)
    expect(confirmation&.confirm_type).to eq('edit_before_type')
  end

  it 'disables an enabled mount through Mounts and Umount and records edit_before for enabled' do
    fixture = create_mount_fixture(enabled: true)
    mount = fixture.fetch(:mount)

    chain, = described_class.fire(mount, enabled: false)
    confirmation = confirmations_for(chain).find do |row|
      row.class_name == 'Mount' && row.row_pks == { 'id' => mount.id } && row.attr_changes == { 'enabled' => 1 }
    end

    expect(tx_classes(chain)).to include(
      Transactions::Vps::Mounts,
      Transactions::Vps::Umount,
      Transactions::Utils::NoOp
    )
    expect(tx_classes(chain)).not_to include(Transactions::Vps::Mount)
    expect(mount.reload.enabled).to be(false)
    expect(confirmation&.confirm_type).to eq('edit_before_type')
  end

  it 'toggles master_enabled without changing enabled and records edit_before for master_enabled' do
    fixture = create_mount_fixture(enabled: true, master_enabled: false)
    mount = fixture.fetch(:mount)

    chain, = described_class.fire(mount, master_enabled: true)
    confirmation = confirmations_for(chain).find do |row|
      row.class_name == 'Mount' &&
        row.row_pks == { 'id' => mount.id } &&
        row.attr_changes == { 'master_enabled' => 0 }
    end

    expect(tx_classes(chain)).to include(
      Transactions::Vps::Mounts,
      Transactions::Vps::Mount,
      Transactions::Utils::NoOp
    )
    expect(tx_classes(chain)).not_to include(Transactions::Vps::Umount)
    expect(mount.reload.master_enabled).to be(true)
    expect(confirmation&.confirm_type).to eq('edit_before_type')
  end

  it 'updates on_start_fail without remounting and records edit_before for the original enum value' do
    fixture = create_mount_fixture(on_start_fail: :mount_later)
    mount = fixture.fetch(:mount)

    chain, = described_class.fire(mount, on_start_fail: :wait_for_mount)
    confirmation = confirmations_for(chain).find do |row|
      row.class_name == 'Mount' &&
        row.row_pks == { 'id' => mount.id } &&
        row.attr_changes == { 'on_start_fail' => Mount.on_start_fails['mount_later'] }
    end

    expect(tx_classes(chain)).to include(Transactions::Vps::Mounts, Transactions::Utils::NoOp)
    expect(tx_classes(chain)).not_to include(Transactions::Vps::Mount, Transactions::Vps::Umount)
    expect(mount.reload.on_start_fail).to eq('wait_for_mount')
    expect(confirmation&.confirm_type).to eq('edit_before_type')
  end

  it 'raises for unsupported attributes and rolls back the attempted change' do
    fixture = create_mount_fixture
    mount = fixture.fetch(:mount)

    expect do
      described_class.fire(mount, dst: '/mnt/other')
    end.to raise_error(RuntimeError, "unsupported attribute 'dst'")

    expect(mount.reload.dst).to eq('/mnt/data')
  end
end
