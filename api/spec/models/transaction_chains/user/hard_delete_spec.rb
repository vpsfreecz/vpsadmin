# frozen_string_literal: true

require 'spec_helper'

RSpec.describe TransactionChains::User::HardDelete do
  around do |example|
    unlock_transaction_signer!
    with_current_context(user: SpecSeed.admin) { example.run }
  end

  def create_download!(user:, snapshot:, pool:)
    SnapshotDownload.create!(
      user: user,
      snapshot: snapshot,
      from_snapshot: nil,
      pool: pool,
      secret_key: SecureRandom.hex(16),
      file_name: 'download.dat.gz',
      confirmed: SnapshotDownload.confirmed(:confirmed),
      format: :stream,
      object_state: :active,
      expiration_date: Time.now + 7.days
    )
  end

  def create_hard_delete_fixture
    user = create_lifecycle_user!
    fixture = create_user_lifecycle_fixture!(user: user, token_session: false)
    backup_pool = create_pool!(node: SpecSeed.other_node, role: :backup)
    backup_dip = attach_dataset_to_pool!(dataset: fixture.fetch(:dataset), pool: backup_pool)
    snapshot, = create_snapshot!(
      dataset: fixture.fetch(:dataset),
      dip: fixture.fetch(:dataset_in_pool),
      name: 'hard-delete-snap'
    )
    download = create_download!(user: user, snapshot: snapshot, pool: fixture.fetch(:pool))
    snapshot.update!(snapshot_download_id: download.id)
    userns, userns_map = create_user_namespace_with_map!(user: user, block_count: 2)
    attach_blocks_to_user_namespace!(userns)
    token_session = create_detached_token_session!(user: user)
    public_key = create_user_public_key!(
      user: user,
      key: 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINixoscreate create@test',
      auto_add: false
    )
    user_data = create_vps_user_data!(
      user: user,
      format: 'script',
      content: "#!/bin/sh\necho spec\n"
    )
    totp = UserTotpDevice.create!(
      user: user,
      label: 'Spec TOTP',
      secret: ROTP::Base32.random_base32,
      recovery_code: 'recovery',
      confirmed: true,
      enabled: true
    )
    webauthn = WebauthnCredential.create!(
      user: user,
      external_id: SecureRandom.hex(16),
      public_key: 'public-key',
      label: 'Spec WebAuthn',
      sign_count: 0
    )
    tsig = create_dns_tsig_key!(user: user)

    fixture.merge(
      user: user,
      backup_dip: backup_dip,
      snapshot_download: download,
      user_namespace: userns,
      user_namespace_map: userns_map,
      token_session: token_session,
      public_key: public_key,
      user_data: user_data,
      totp: totp,
      webauthn: webauthn,
      tsig: tsig
    )
  end

  it 'cascades through VPSes, exports, backups, downloads, DNS, namespaces, and local credentials' do
    fixture = create_hard_delete_fixture
    user = fixture.fetch(:user)

    chain, = described_class.fire(user, true, nil, ObjectState.new)
    classes = tx_classes(chain)
    confirmations = confirmations_for(chain)
    models = confirmations.map(&:class_name)

    expect(classes).to include(
      Transactions::Vps::Destroy,
      Transactions::Export::Destroy,
      Transactions::Storage::DestroyDataset,
      Transactions::Storage::RemoveDownload,
      Transactions::DnsServerZone::DeleteRecords,
      Transactions::DnsServerZone::Destroy,
      Transactions::UserNamespace::DisuseMap,
      Transactions::Utils::NoOp
    )
    expect(confirmations.any? do |row|
      row.class_name == 'Vps' &&
        row.row_pks == { 'id' => fixture.fetch(:vps).id } &&
        row.attr_changes.is_a?(Hash) &&
        row.attr_changes['object_state'] == Vps.object_states[:hard_delete]
    end).to be(true)
    expect(confirmations.any? do |row|
      row.class_name == 'Export' &&
        row.row_pks == { 'id' => fixture.fetch(:export).id } &&
        row.confirm_type == 'destroy_type'
    end).to be(true)
    expect(confirmations.any? do |row|
      row.class_name == 'DatasetInPool' &&
        row.row_pks == { 'id' => fixture.fetch(:backup_dip).id } &&
        row.confirm_type == 'destroy_type'
    end).to be(true)
    expect(confirmations.any? do |row|
      row.class_name == 'SnapshotDownload' &&
        row.row_pks == { 'id' => fixture.fetch(:snapshot_download).id } &&
        row.confirm_type == 'destroy_type'
    end).to be(true)
    expect(confirmations.any? do |row|
      row.class_name == 'DnsRecord' &&
        row.row_pks == { 'id' => fixture.fetch(:user_record).id } &&
        row.confirm_type == 'destroy_type'
    end).to be(true)
    expect(confirmations.any? do |row|
      row.class_name == 'DnsZone' &&
        row.row_pks == { 'id' => fixture.fetch(:owned_zone).id } &&
        row.confirm_type == 'destroy_type'
    end).to be(true)
    expect(confirmations.any? do |row|
      row.class_name == 'UserNamespaceMap' &&
        row.row_pks == { 'id' => fixture.fetch(:user_namespace_map).id } &&
        row.confirm_type == 'just_destroy_type'
    end).to be(true)
    expect(confirmations.any? do |row|
      row.class_name == 'UserNamespace' &&
        row.row_pks == { 'id' => fixture.fetch(:user_namespace).id } &&
        row.confirm_type == 'just_destroy_type'
    end).to be(true)

    expect(models).to include(
      'DnsTsigKey',
      'UserPublicKey',
      'VpsUserData',
      'UserTotpDevice',
      'WebauthnCredential',
      'User'
    )
    user_edit = confirmations.find do |row|
      row.class_name == 'User' &&
        row.row_pks == { 'id' => user.id } &&
        row.attr_changes.is_a?(Hash) &&
        row.attr_changes.has_key?('login')
    end

    expect(user_edit.attr_changes).to include('login' => nil, 'password' => '!')
  end
end
