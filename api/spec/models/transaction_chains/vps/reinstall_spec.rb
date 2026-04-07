# frozen_string_literal: true

require 'spec_helper'

RSpec.describe TransactionChains::Vps::Reinstall do
  around do |example|
    unlock_transaction_signer!
    with_current_context(user: user) { example.run }
  end

  let(:user) { SpecSeed.user }

  def create_reinstall_fixture
    pool = create_pool!(node: SpecSeed.node, role: :hypervisor)
    create_port_reservations!(node: SpecSeed.node)
    backup_node = create_node!(
      location: SpecSeed.location,
      role: :storage,
      name: "reinstall-backup-#{SecureRandom.hex(3)}"
    )
    create_port_reservations!(node: backup_node)
    backup_pool = create_pool!(
      node: backup_node,
      role: :backup,
      filesystem: "spec_backup_#{SecureRandom.hex(4)}"
    )
    dataset, dip = create_dataset_with_pool!(
      user: user,
      pool: pool,
      name: "reinstall-root-#{SecureRandom.hex(4)}"
    )
    backup_dip = attach_dataset_to_pool!(dataset: dataset, pool: backup_pool)

    ensure_numeric_resources!(user: user, environment: SpecSeed.node.location.environment)
    allocate_dip_diskspace!(dip, user: user, value: 10_240)

    vps = create_vps_for_dataset!(user: user, node: SpecSeed.node, dataset_in_pool: dip)
    allocate_vps_resources!(vps, user: user)
    seed_vps_features!(vps)

    tree = create_tree!(dip: backup_dip, head: true)
    create_branch!(tree: tree, name: 'head', head: true)

    [dataset, dip, vps, backup_dip]
  end

  it 'stops, destroys local snapshots, detaches backup heads, reinstalls, reapplies features, and stays stopped without user data' do
    dataset, dip, vps, backup_dip = create_reinstall_fixture
    create_snapshot!(dataset: dataset, dip: dip, name: 'snap-a')
    create_snapshot!(dataset: dataset, dip: dip, name: 'snap-b')

    chain, = described_class.fire(vps, vps.os_template, {})

    expect(tx_classes(chain)).to include(
      Transactions::Vps::Stop,
      Transactions::Storage::DestroySnapshot,
      Transactions::Vps::Reinstall,
      Transactions::Vps::Features
    )
    expect(tx_classes(chain).count(Transactions::Storage::DestroySnapshot)).to eq(2)
    expect(tx_classes(chain)).not_to include(
      Transactions::Vps::Start,
      Transactions::Vps::DeployUserData,
      Transactions::Vps::ApplyUserData,
      Transactions::Vps::DeployPublicKey
    )
    expect(confirmation_attr_changes(chain, 'DatasetTree', confirm_type: :edit_after_type)).to include(
      include('head' => 0)
    )
    expect(confirmation_attr_changes(chain, 'Branch', confirm_type: :edit_after_type)).to include(
      include('head' => 0)
    )
    expect(confirmation_attr_changes(chain, 'Dataset', confirm_type: :increment_type)).to include(
      'current_history_id'
    )
    expect(backup_dip.dataset_trees.find_by!(head: true)).not_to be_nil
  end

  it 'reinstalls a running VPS, redeploys auto-add keys with keep-going, deploys NixOS user data, and restarts keep-going' do
    _dataset, _dip, vps, = create_reinstall_fixture
    set_vps_running!(vps, is_running: true)
    create_user_public_key!(
      user: user,
      label: 'Auto Reinstall Key',
      key: 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIreinstall reinstall@test',
      auto_add: true
    )
    template = create_os_template!(distribution: 'nixos', config: { 'datasets' => [{ 'name' => '/' }] })
    user_data = create_vps_user_data!(
      user: user,
      format: 'nixos_configuration',
      content: '{ config, pkgs, ... }: { }'
    )

    chain, = described_class.fire(vps, template, vps_user_data: user_data)
    classes = tx_classes(chain)
    deploy_key_rows = transactions_for(chain).select do |tx|
      Transaction.for_type(tx.handle) == Transactions::Vps::DeployPublicKey
    end
    start_tx = transactions_for(chain).find do |tx|
      Transaction.for_type(tx.handle) == Transactions::Vps::Start
    end

    expect(classes).to include(
      Transactions::Vps::Stop,
      Transactions::Vps::Reinstall,
      Transactions::Vps::Features,
      Transactions::Vps::DeployPublicKey,
      Transactions::Vps::DeployUserData,
      Transactions::Vps::Start,
      Transactions::Vps::ApplyUserData
    )
    expect(tx_payload(chain, Transactions::Vps::Reinstall)).to include('distribution' => 'nixos')
    expect(tx_payload(chain, Transactions::Vps::DeployUserData)).to include(
      'format' => 'nixos_configuration',
      'os_template' => include('distribution' => 'nixos')
    )
    expect(tx_payload(chain, Transactions::Vps::ApplyUserData)).to include(
      'format' => 'nixos_configuration',
      'os_template' => include('distribution' => 'nixos')
    )
    expect(deploy_key_rows).not_to be_empty
    expect(deploy_key_rows.map(&:reversible).uniq).to eq(['keep_going'])
    expect(start_tx.reversible).to eq('keep_going')
    expect(classes.index(Transactions::Vps::DeployUserData)).to be < classes.index(Transactions::Vps::Start)
    expect(classes.index(Transactions::Vps::Start)).to be < classes.index(Transactions::Vps::ApplyUserData)
  end
end
