# frozen_string_literal: true

require 'spec_helper'

RSpec.describe VpsAdmin::API::Operations::Node::ReconstructKernelEvents do
  let(:node) { SpecSeed.node }
  let(:t0) { Time.utc(2026, 7, 1, 12, 0, 0) }

  def create_status(time:, uptime:, kernel:)
    NodeStatus.create!(
      node:,
      uptime:,
      kernel:,
      vpsadmin_version: 'spec',
      created_at: time
    )
  end

  before do
    node.node_statuses.delete_all
    node.node_kernel_events.delete_all
    node.node_kernel_history_state&.destroy!
  end

  it 'reconstructs boots and same-boot reported release changes' do
    create_status(time: t0 + 100, uptime: 100, kernel: '6.12.93')
    create_status(time: t0 + 1_000, uptime: 1_000, kernel: '6.12.93')
    create_status(time: t0 + 1_900, uptime: 1_900, kernel: '6.12.93.1')
    create_status(time: t0 + 3_700, uptime: 100, kernel: '6.12.95')

    expect(described_class.run(node, batch_size: 2)).to eq(3)

    events = node.node_kernel_events.order(:observed_before).to_a
    expect(events.map(&:event_type)).to eq(%w[boot reported_release_change boot])
    expect(events.map(&:reported_release)).to eq(%w[6.12.93 6.12.93.1 6.12.95])
    expect(events.first.booted_at).to be_within(1.second).of(t0)
    expect(events.second.observed_after).to eq(t0 + 1_000)
    expect(events.last).to be_current
    expect(events[0..1]).to all(be_inferred)
    state = node.reload.node_kernel_history_state
    expect(state.from_status_id).to eq(node.node_statuses.order(:created_at, :id).first.id)
    expect(state.through_status_id).to eq(node.node_statuses.order(:created_at, :id).last.id)
  end

  it 'recognizes a same-kernel reboot from decreasing uptime' do
    create_status(time: t0 + 1_000, uptime: 1_000, kernel: '6.12.95')
    create_status(time: t0 + 1_100, uptime: 10, kernel: '6.12.95')

    described_class.run(node, batch_size: 1)

    expect(node.node_kernel_events.boot.count).to eq(2)
  end

  it 'records gaps in the source status samples used for reconstruction' do
    create_status(time: t0 + 100, uptime: 100, kernel: '6.12.95')
    create_status(time: t0 + 3_700, uptime: 3_700, kernel: '6.12.95')

    described_class.run(node, batch_size: 1)

    expect(
      node.reload.node_kernel_history_state.kernel_history_gaps.pluck(:from, :to, :reason)
    ).to eq([[
              t0 + 100,
              t0 + 3_700,
              'node status sampling gap'
            ]])
  end

  it 'is idempotent' do
    create_status(time: t0 + 100, uptime: 100, kernel: '6.12.95')

    described_class.run(node)
    ids = node.node_kernel_events.order(:id).pluck(:id)
    checkpoint_updated_at = node.reload.node_kernel_history_state.updated_at
    expect(described_class.run(node)).to eq(0)

    expect(node.node_kernel_events.count).to eq(1)
    expect(node.node_kernel_events.order(:id).pluck(:id)).to eq(ids)
    expect(node.reload.node_kernel_history_state.updated_at).to eq(checkpoint_updated_at)
  end

  it 'keeps completed history complete until an explicit forced rerun' do
    create_status(time: t0 + 100, uptime: 100, kernel: '6.12.93')
    described_class.run(node)
    first_checkpoint = node.reload.node_kernel_history_state
    create_status(time: t0 + 200, uptime: 10, kernel: '6.12.95')

    expect(described_class.run(node)).to eq(0)
    expect(node.node_kernel_events.count).to eq(1)
    expect(node.reload.node_kernel_history_state.updated_at).to eq(first_checkpoint.updated_at)

    expect(described_class.run(node, force: true, batch_size: 1)).to eq(1)
    expect(node.node_kernel_events.order(:observed_before).pluck(:reported_release)).to eq(
      %w[6.12.93 6.12.95]
    )
    expect(node.reload.node_kernel_history_state.through_status_id).to eq(
      node.node_statuses.order(:created_at, :id).last.id
    )
  end

  it 'retains reconstructed and node-reported evidence as append-only records' do
    status = create_status(time: t0 + 100, uptime: 100, kernel: '6.12.95')
    NodeKernelEvent.create!(
      node:,
      event_type: :boot,
      source: :node_report,
      confidence: :exact,
      boot_id: 'boot-a',
      booted_at: t0,
      booted_release: '6.12.95',
      reported_release: '6.12.95',
      effective_at: t0,
      observed_before: t0 + 120,
      current: true
    )

    described_class.run(node, batch_size: 1)

    expect(node.node_kernel_events.kernel_history.count).to eq(2)
    reconstructed = node.node_kernel_events.reconstructed_node_status.first
    expect(reconstructed.source_status_id).to eq(status.id)
    expect(node.node_kernel_events.node_report.first).to be_current
  end

  it 'stops backfill before exact reporting and never supersedes exact current state' do
    historical = create_status(time: t0 + 100, uptime: 100, kernel: '6.12.93')
    exact = NodeKernelEvent.create!(
      node:,
      event_type: :boot,
      source: :node_report,
      confidence: :exact,
      boot_id: 'boot-a',
      booted_at: t0,
      booted_release: '6.12.93',
      reported_release: '6.12.93',
      effective_at: t0,
      observed_before: t0 + 120,
      current: true
    )
    post_exact = create_status(time: t0 + 180, uptime: 180, kernel: '6.12.93')

    described_class.run(node)

    reconstructed = node.node_kernel_events.reconstructed_node_status
    expect(reconstructed.pluck(:source_status_id)).to eq([historical.id])
    expect(reconstructed.pluck(:source_status_id)).not_to include(post_exact.id)
    expect(exact.reload).to be_current
    expect(node.reload.node_kernel_history_state.through_status_id).to eq(historical.id)
  end

  it 'uses the same Node row lock for reconstruction and exact reporting' do
    create_status(time: t0 + 100, uptime: 100, kernel: '6.12.95')
    evidence = {
      'schema_version' => 1,
      'kernel' => {
        'boot_id' => 'boot-a',
        'booted_at' => t0.iso8601,
        'booted_release' => '6.12.95',
        'reported_release' => '6.12.95',
        'kernel_source_revision' => 'linux-revision',
        'config_digest' => 'a' * 64,
        'booted_params' => [],
        'command_line' => ''
      },
      'livepatches' => [],
      'ebpf_programs' => [],
      'loaded_modules' => [],
      'sysctls' => {},
      'deployment' => {
        'booted_system' => '/nix/store/booted',
        'current_system' => '/nix/store/current'
      },
      'software_versions' => [],
      'errors' => []
    }
    allow(node).to receive(:with_lock).and_call_original

    described_class.run(node)
    VpsAdmin::API::Operations::Node::RecordKernelEvidence.run(
      node:,
      observed_at: t0 + 120,
      report: VpsAdmin::API::KernelEvidence::Report.from_hash(evidence)
    )

    expect(node).to have_received(:with_lock).twice
    current = node.node_kernel_events.kernel_history.where(current: true).sole
    expect(current).to be_node_report
    expect(current.boot_id).to eq('boot-a')
  end

  it 'does not reconstruct host kernel history for service-only nodes' do
    create_status(time: t0 + 100, uptime: 100, kernel: 'host-kernel')
    node.update!(role: :dns_server)

    expect(described_class.run(node)).to eq(0)
    expect(node.node_kernel_events).to be_empty
    expect(node.node_kernel_history_state).to be_nil
  ensure
    node.update!(role: :node)
  end

  it 'rolls back events when the completion checkpoint cannot be written' do
    create_status(time: t0 + 100, uptime: 100, kernel: '6.12.95')
    checkpoint = NodeKernelHistoryState.new(node:)
    allow(NodeKernelHistoryState).to receive(:find_or_initialize_by).and_return(checkpoint)
    allow(checkpoint).to receive(:save!).and_raise('checkpoint failed')

    expect { described_class.run(node) }.to raise_error('checkpoint failed')
    expect(node.node_kernel_events.reload).to be_empty
    expect(NodeKernelHistoryState.where(node:)).to be_empty
  end

  it 'retries an unlocked scan when exact ingestion establishes a cutoff' do
    historical = create_status(time: t0 + 100, uptime: 100, kernel: '6.12.93')
    after_exact = create_status(time: t0 + 200, uptime: 200, kernel: '6.12.93')
    exact = nil
    lock_held = false
    progress = Object.new
    allow(node).to receive(:with_lock).and_wrap_original do |original, *args, &write|
      original.call(*args) do
        lock_held = true
        begin
          write.call
        ensure
          lock_held = false
        end
      end
    end
    allow(progress).to receive(:start)
    allow(progress).to receive(:finish)
    allow(progress).to receive(:failed)
    allow(progress).to receive(:retry)
    allow(progress).to receive(:advance) do
      next if exact

      expect(lock_held).to be(false)
      exact = NodeKernelEvent.create!(
        node:,
        event_type: :boot,
        source: :node_report,
        confidence: :exact,
        boot_id: 'concurrent-boot',
        booted_at: t0,
        booted_release: '6.12.93',
        reported_release: '6.12.93',
        effective_at: t0,
        observed_before: t0 + 150,
        current: true
      )
    end

    expect(described_class.run(node, batch_size: 1, progress:)).to eq(1)

    expect(progress).to have_received(:retry).once
    expect(node.node_kernel_events.reconstructed_node_status.pluck(:source_status_id)).to eq(
      [historical.id]
    )
    expect(node.node_kernel_events.reconstructed_node_status.pluck(:source_status_id)).not_to include(
      after_exact.id
    )
    expect(exact.reload).to be_current
    expect(node.node_kernel_events.kernel_history.where(current: true).count).to eq(1)
  end

  it 'bounds retries when status ingestion changes every unlocked scan' do
    create_status(time: t0 + 100, uptime: 100, kernel: '6.12.93')
    attempt = 0
    inserted = false
    progress = Object.new
    allow(progress).to receive(:finish)
    allow(progress).to receive(:failed)
    allow(progress).to receive(:retry)
    allow(progress).to receive(:start) do
      attempt += 1
      inserted = false
    end
    allow(progress).to receive(:advance) do
      next if inserted

      inserted = true
      create_status(
        time: t0 + 100 + attempt,
        uptime: 100 + attempt,
        kernel: '6.12.93'
      )
    end

    expect do
      described_class.run(node, batch_size: 1, progress:)
    end.to raise_error(
      VpsAdmin::API::Operations::Node::HistoryBackfill::ConcurrentChange,
      /4 consecutive scans/
    )

    expect(progress).to have_received(:start).exactly(4).times
    expect(progress).to have_received(:retry).exactly(3).times
    expect(progress).to have_received(:failed).once
    expect(node.node_kernel_events).to be_empty
    expect(node.node_kernel_history_state).to be_nil
  end

  it 'does not instantiate full status records and plucks only kernel columns' do
    create_status(time: t0 + 100, uptime: 100, kernel: '6.12.95')
    sql = []
    subscriber = ActiveSupport::Notifications.subscribe('sql.active_record') do |*, payload|
      sql << payload[:sql] if payload[:sql].include?('node_statuses')
    end
    allow(NodeStatus).to receive(:instantiate).and_raise('full status materialized')

    described_class.run(node, batch_size: 1)

    data_query = sql.find do |query|
      query.include?('created_at') && query.include?('uptime') && query.include?('kernel')
    end
    expect(data_query).to be_present
    expect(data_query).not_to include('cpus', 'total_memory', 'total_swap')
    expect(sql).not_to include(a_string_matching(/node_statuses\.\*/i))
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber) if subscriber
  end
end
