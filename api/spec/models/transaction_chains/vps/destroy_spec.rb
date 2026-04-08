# frozen_string_literal: true

require 'spec_helper'

RSpec.describe TransactionChains::Vps::Destroy do
  around do |example|
    unlock_transaction_signer!
    with_current_context(user: user) { example.run }
  end

  let(:user) { SpecSeed.user }

  def create_destroy_fixture
    fixture = build_standalone_vps_fixture(user: user, hostname: 'destroy-phase2')
    vps = fixture.fetch(:vps)
    pool = fixture.fetch(:pool)
    dataset = fixture.fetch(:dataset)

    _subdataset, sub_dip = create_vps_subdataset!(
      user: user,
      pool: pool,
      parent: dataset,
      name: "destroy-mount-#{SecureRandom.hex(4)}"
    )
    mount = create_mount_record!(vps: vps, dataset_in_pool: sub_dip, dst: '/mnt/data')
    netif = create_network_interface!(vps, name: 'eth0')
    set_vps_running!(vps, is_running: false, status: true, update_count: 1)
    VpsStatus.create!(vps: vps, is_running: false, status: true)

    rule = OomReportRule.create!(
      vps: vps,
      action: :notify,
      cgroup_pattern: 'user.slice'
    )
    OomReport.create!(
      vps: vps,
      oom_report_rule: rule,
      invoked_by_name: 'spec-task',
      invoked_by_pid: 123,
      processed: true
    )
    OomReportCounter.create!(vps: vps, cgroup: '/', counter: 2)
    VpsOsProcess.create!(vps: vps, state: 'R', count: 5)
    VpsSshHostKey.create!(
      vps: vps,
      algorithm: 'ed25519',
      bits: 256,
      fingerprint: 'SHA256:destroyspec'
    )

    export, = create_export_for_dataset!(dataset_in_pool: sub_dip, user: user)
    ExportMount.create!(
      export: export,
      vps: vps,
      mountpoint: '/mnt/export',
      nfs_version: '3'
    )

    {
      fixture: fixture,
      mount: mount,
      netif: netif,
      rule: rule
    }
  end

  it 'stops first, frees resources, removes mounts and netifs, destroys the VPS, and clears dataset links at the end' do
    fixture = create_destroy_fixture
    vps = fixture.fetch(:fixture).fetch(:vps)
    root_dip = fixture.fetch(:fixture).fetch(:dataset_in_pool)
    mount = fixture.fetch(:mount)
    netif = fixture.fetch(:netif)

    chain, = described_class.fire(vps, nil, nil, nil)
    classes = tx_classes(chain)
    stop_payload = tx_payload(chain, Transactions::Vps::Stop)
    clear_confirmation = confirmations_for(chain).find do |row|
      row.class_name == 'Vps' &&
        row.row_pks == { 'id' => vps.id } &&
        row.attr_changes == { 'dataset_in_pool_id' => nil, 'user_namespace_map_id' => nil }
    end
    clear_idx = transactions_for(chain).index(clear_confirmation.parent_transaction)

    expect(classes.first).to eq(Transactions::Vps::Stop)
    expect(stop_payload).to include('rollback_stop' => false)
    expect(classes).to include(
      Transactions::Vps::Umount,
      Transactions::Vps::Mounts,
      Transactions::Vps::Destroy,
      Transactions::UserNamespace::DisuseMap
    )
    expect(classes).not_to include(Transactions::Storage::DestroyDataset)
    expect(classes.index(Transactions::Vps::Stop)).to be < classes.index(Transactions::Vps::Umount)
    expect(classes.index(Transactions::Vps::Umount)).to be < classes.index(Transactions::Vps::Mounts)
    expect(classes.index(Transactions::Vps::Mounts)).to be < classes.index(Transactions::Vps::Destroy)
    expect(classes.index(Transactions::Vps::Destroy)).to be < classes.index(Transactions::UserNamespace::DisuseMap)
    expect(clear_idx).to be > classes.index(Transactions::UserNamespace::DisuseMap)

    expect(chain.concern_type).to eq('chain_affect')
    expect(chain.transaction_chain_concerns.pluck(:class_name, :row_id)).to include(['Vps', vps.id])
    expect(chain.locks.map { |lock| [lock.resource, lock.row_id] }).to include(
      ['Vps', vps.id],
      ['DatasetInPool', root_dip.id]
    )

    expect(root_dip.reload.confirmed).to eq(:confirm_destroy)
    expect(ClusterResourceUse.where(class_name: 'Vps', row_id: vps.id).pluck(:confirmed).uniq).to eq(
      [ClusterResourceUse.confirmed(:confirm_destroy)]
    )
    expect(ClusterResourceUse.where(class_name: 'DatasetInPool', row_id: root_dip.id).pluck(:confirmed).uniq).to eq(
      [ClusterResourceUse.confirmed(:confirm_destroy)]
    )

    expect(confirmations_for(chain).any? do |row|
      row.class_name == 'Mount' &&
        row.row_pks == { 'id' => mount.id } &&
        row.confirm_type == 'destroy_type'
    end).to be(true)
    expect(confirmations_for(chain).any? do |row|
      row.class_name == 'NetworkInterface' &&
        row.row_pks == { 'id' => netif.id } &&
        row.confirm_type == 'just_destroy_type'
    end).to be(true)
    expect(confirmations_for(chain).any? do |row|
      row.class_name == 'VpsCurrentStatus' &&
        row.row_pks == { 'id' => vps.vps_current_status.id } &&
        row.confirm_type == 'just_destroy_type'
    end).to be(true)

    expect(vps.oom_reports.count).to eq(0)
    expect(vps.oom_report_counters.count).to eq(0)
    expect(vps.vps_os_processes.count).to eq(0)
    expect(vps.vps_ssh_host_keys.count).to eq(0)
    expect(vps.export_mounts.count).to eq(0)
    expect(vps.vps_statuses.count).to eq(0)
  end

  it 'raises for snapshot mounts before composing the destroy chain' do
    fixture = build_standalone_vps_fixture(user: user, hostname: 'destroy-snapshot-mount')
    dataset = fixture.fetch(:dataset)
    dip = fixture.fetch(:dataset_in_pool)
    vps = fixture.fetch(:vps)
    snapshot, snapshot_in_pool = create_snapshot!(dataset: dataset, dip: dip, name: 'destroy-snap')
    create_snapshot_mount_record!(vps: vps, snapshot_in_pool: snapshot_in_pool, dst: '/mnt/snapshot')

    expect do
      described_class.fire(vps, nil, nil, nil)
    end.to raise_error(RuntimeError, 'snapshot mounts are not supported')

    expect(snapshot).to be_present
  end
end
