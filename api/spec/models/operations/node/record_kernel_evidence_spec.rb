# frozen_string_literal: true

require 'spec_helper'

RSpec.describe VpsAdmin::API::Operations::Node::RecordKernelEvidence do
  let(:node) { SpecSeed.node }
  let(:t0) { Time.utc(2026, 7, 1, 12, 0, 0) }

  def evidence(
    boot_id: 'boot-a',
    release: '6.12.93',
    livepatches: [],
    ebpf_programs: [],
    modules: ['kvm'],
    current_system: '/nix/store/system-a',
    software_versions: [],
    booted_at: t0.iso8601,
    errors: []
  )
    {
      'schema_version' => 1,
      'kernel' => {
        'boot_id' => boot_id,
        'booted_at' => booted_at,
        'booted_release' => '6.12.93',
        'reported_release' => release,
        'kernel_source_revision' => 'linux-revision',
        'config_digest' => 'a' * 64,
        'booted_params' => [],
        'command_line' => ''
      },
      'livepatches' => livepatches.map do |livepatch|
        {
          'kernel_version' => '6.12.93',
          'patch_version' => 1,
          'loaded' => true,
          'enabled' => false,
          'transition' => false,
          'applied_at' => nil,
          'verified_at' => nil,
          'patches' => []
        }.merge(livepatch)
      end,
      'ebpf_programs' => ebpf_programs.map do |program|
        {
          'description' => nil,
          'sinceKernel' => nil,
          'untilKernel' => nil,
          'revision' => 'revision',
          'digest' => 'digest',
          'active' => false,
          'attached_at' => nil,
          'verified_at' => nil,
          'bpfPrograms' => [],
          'links' => {}
        }.merge(program)
      end,
      'loaded_modules' => modules,
      'software_versions' => software_versions,
      'sysctls' => {
        'kernel.dmesg_restrict' => {
          'available' => true,
          'configured' => 1,
          'effective' => '1'
        }
      },
      'deployment' => {
        'booted_system' => '/nix/store/system-a',
        'current_system' => current_system
      },
      'errors' => errors
    }
  end

  def software_versions(revisions = {})
    %w[booted current].product(%w[vpsadminos vpsadmin nixpkgs]).map do |generation, component|
      key = "#{generation}.#{component}"
      {
        'generation' => generation,
        'component' => component,
        'version' => "#{component}-version",
        'version_source' => 'native',
        'revision' => Digest::SHA1.hexdigest(revisions.fetch(key, "#{generation}-#{component}-a")),
        'revision_source' => 'native',
        'revision_dirty' => false
      }
    end
  end

  def report(value)
    VpsAdmin::API::KernelEvidence::Report.from_hash(value)
  end

  def stored_report(snapshot)
    VpsAdmin::API::KernelEvidence::SnapshotReader.call(snapshot)
  end

  def event_snapshot(value, observed_at: t0 + 90)
    VpsAdmin::API::KernelEvidence::SnapshotWriter.call(
      snapshot: NodeKernelEvidence.new(node:, snapshot_type: :event),
      report: report(value),
      observed_at:,
      received_at: observed_at
    )
  end

  def capture_sql(&block)
    statements = []
    callback = lambda do |*, payload|
      statements << payload[:sql] unless payload[:name] == 'SCHEMA'
    end
    ActiveSupport::Notifications.subscribed(callback, 'sql.active_record', &block)
    statements
  end

  before do
    node.node_kernel_events.delete_all
  end

  it 'records a boot and a verified same-boot livepatch change' do
    initial = evidence
    patched = evidence(
      release: '6.12.93.1',
      livepatches: [{
        'id' => 'livepatch_1',
        'enabled' => true,
        'applied_at' => (t0 + 60).iso8601
      }]
    )

    described_class.run(node:, observed_at: t0 + 10, report: report(initial))
    described_class.run(
      node:,
      observed_at: t0 + 120,
      report: report(patched),
      previous_report: report(initial),
      previous_observed_at: t0 + 10
    )

    events = node.node_kernel_events.kernel_history.order(:observed_before).to_a
    expect(events.map(&:event_type)).to eq(%w[boot livepatch_change])
    expect(events.first).not_to be_current
    expect(events.last).to be_current
    expect(events.last.observed_after).to eq(t0 + 10)
    expect(events.first.effective_at).to eq(t0)
    expect(events.first).to be_exact
    expect(events.last).to be_exact
    expect(events.last.effective_at).to eq(t0 + 60)
  end

  it 'marks a boot time estimated from uptime as inferred' do
    initial = evidence(errors: [{
      'component' => 'booted_at',
      'reason' => 'estimated_from_uptime'
    }])

    described_class.run(node:, observed_at: t0 + 10, report: report(initial))

    boot = node.node_kernel_events.boot.sole
    expect(boot).to be_inferred
    expect(boot.kernel_evidence.kernel_evidence_errors.sole).to have_attributes(
      component: 'booted_at',
      reason: 'estimated_from_uptime'
    )
  end

  it 'marks a reported boot without a timestamp as incomplete' do
    described_class.run(
      node:,
      observed_at: t0 + 10,
      report: report(evidence(booted_at: nil))
    )

    expect(node.node_kernel_events.boot.sole).to be_incomplete
  end

  it 'records internal runtime evidence changes without replacing the current kernel event' do
    initial = evidence
    changed = evidence(modules: %w[kvm kvm_amd])

    described_class.run(node:, observed_at: t0 + 10, report: report(initial))
    described_class.run(
      node:,
      observed_at: t0 + 120,
      report: report(changed),
      previous_report: report(initial),
      previous_observed_at: t0 + 10
    )

    expect(node.node_kernel_events.module_change.count).to eq(1)
    expect(node.node_kernel_events.kernel_history.where(current: true).count).to eq(1)
  end

  it 'shares one immutable evidence snapshot among changes from one report' do
    initial = evidence
    changed = evidence(
      modules: %w[kvm kvm_amd],
      current_system: '/nix/store/system-b'
    )
    changed['sysctls']['kernel.dmesg_restrict']['effective'] = '0'

    described_class.run(node:, observed_at: t0 + 10, report: report(initial))
    described_class.run(
      node:,
      observed_at: t0 + 120,
      report: report(changed),
      previous_report: report(initial),
      previous_observed_at: t0 + 10
    )

    changes = node.node_kernel_events.where(
      event_type: %i[module_change sysctl_change deployment_change]
    )
    expect(changes.count).to eq(3)
    expect(changes.distinct.pluck(:node_kernel_evidence_id).length).to eq(1)
    expect(changes.first.kernel_evidence).to be_event
  end

  it 'records a same-boot system activation as an internal deployment change' do
    initial = evidence
    activated = evidence(current_system: '/nix/store/system-b')

    described_class.run(node:, observed_at: t0 + 10, report: report(initial))
    described_class.run(
      node:,
      observed_at: t0 + 120,
      report: report(activated),
      previous_report: report(initial),
      previous_observed_at: t0 + 10
    )

    change = node.node_kernel_events.deployment_change.sole
    expect(stored_report(change.kernel_evidence).to_h.fetch('deployment')).to eq(
      'booted_system' => '/nix/store/system-a',
      'current_system' => '/nix/store/system-b'
    )
    expect(node.node_kernel_events.kernel_history.where(current: true).count).to eq(1)
  end

  it 'groups simultaneous software changes and records the initial baseline' do
    initial = evidence(software_versions: software_versions)
    activated = evidence(
      current_system: '/nix/store/system-b',
      software_versions: software_versions(
        'current.vpsadminos' => 'current-vpsadminos-b',
        'current.nixpkgs' => 'current-nixpkgs-b'
      )
    )

    described_class.run(node:, observed_at: t0 + 10, report: report(initial))
    described_class.run(
      node:,
      observed_at: t0 + 120,
      report: report(activated),
      previous_report: report(initial),
      previous_observed_at: t0 + 10
    )

    boot = node.node_kernel_events.boot.sole
    deployment = node.node_kernel_events.deployment_change.sole
    expect(boot.software_changes.count).to eq(6)
    expect(deployment.software_changes.pluck(:generation, :component)).to contain_exactly(
      %w[current vpsadminos],
      %w[current nixpkgs]
    )
  end

  it 'records per-name sysctl values before and after a change' do
    initial = evidence
    changed = evidence
    changed['sysctls']['kernel.dmesg_restrict'] = {
      'available' => true,
      'configured' => 1,
      'effective' => '0'
    }

    described_class.run(node:, observed_at: t0 + 10, report: report(initial))
    described_class.run(
      node:,
      observed_at: t0 + 120,
      report: report(changed),
      previous_report: report(initial),
      previous_observed_at: t0 + 10
    )

    change = node.node_kernel_events.sysctl_change.sole.sysctl_changes.sole
    expect(change.name).to eq('kernel.dmesg_restrict')
    expect(change.before_effective_value).to eq('1')
    expect(change.after_effective_value).to eq('0')
  end

  it 'records added and removed sysctls without a separate policy identity' do
    initial = evidence
    changed = evidence
    changed['sysctls'].delete('kernel.dmesg_restrict')
    changed['sysctls']['kernel.kptr_restrict'] = {
      'available' => true,
      'configured' => 2,
      'effective' => '2'
    }

    described_class.run(node:, observed_at: t0 + 10, report: report(initial))
    described_class.run(
      node:,
      observed_at: t0 + 120,
      report: report(changed),
      previous_report: report(initial),
      previous_observed_at: t0 + 10
    )

    changes = node.node_kernel_events.sysctl_change.sole.sysctl_changes.index_by(&:name)
    expect(changes.keys).to contain_exactly('kernel.dmesg_restrict', 'kernel.kptr_restrict')
    expect(changes.fetch('kernel.dmesg_restrict').after_available).to be_nil
    expect(changes.fetch('kernel.kptr_restrict').before_available).to be_nil
    expect(stored_report(node.node_kernel_events.sysctl_change.sole.kernel_evidence).sysctls.keys)
      .to eq(['kernel.kptr_restrict'])
  end

  it 'does not record an eBPF change when only its verification time advances' do
    initial = evidence(ebpf_programs: [{
      'name' => 'guard',
      'active' => true,
      'attached_at' => (t0 + 30).iso8601,
      'verified_at' => (t0 + 60).iso8601
    }])
    verified_again = Marshal.load(Marshal.dump(initial))
    verified_again['ebpf_programs'][0]['verified_at'] = (t0 + 120).iso8601

    described_class.run(node:, observed_at: t0 + 10, report: report(initial))
    described_class.run(
      node:,
      observed_at: t0 + 130,
      report: report(verified_again),
      previous_report: report(initial),
      previous_observed_at: t0 + 10
    )

    expect(node.node_kernel_events.ebpf_change.count).to eq(0)
  end

  it 'deletes a matching reconstructed boot when exact identity first arrives' do
    reconstructed = NodeKernelEvent.create!(
      node:,
      event_type: :boot,
      source: :reconstructed_node_status,
      confidence: :inferred,
      booted_at: t0,
      booted_release: '6.12.93',
      reported_release: '6.12.93',
      effective_at: t0,
      observed_before: t0 + 60,
      current: true
    )

    described_class.run(node:, observed_at: t0 + 120, report: report(evidence))

    expect(node.node_kernel_events.count).to eq(1)
    reported = node.node_kernel_events.kernel_history.sole
    expect(reported).to be_node_report
    expect(reported).to be_exact
    expect(reported.boot_id).to eq('boot-a')
    expect(reported.effective_at).to eq(t0)
    expect(NodeKernelEvent.exists?(reconstructed.id)).to be(false)
  end

  it 'keeps an unmatched reconstructed boot visible as a distinct reboot' do
    reconstructed = NodeKernelEvent.create!(
      node:,
      event_type: :boot,
      source: :reconstructed_node_status,
      confidence: :inferred,
      booted_at: t0 - 1.hour,
      booted_release: '6.12.93',
      reported_release: '6.12.93',
      effective_at: t0 - 1.hour,
      observed_before: t0 - 50.minutes,
      current: true
    )

    described_class.run(node:, observed_at: t0 + 120, report: report(evidence))

    expect(node.node_kernel_events.kernel_history.count).to eq(2)
    expect(NodeKernelEvent.exists?(reconstructed.id)).to be(true)
    expect(node.node_kernel_events.node_report.boot.sole.effective_at).to eq(t0)
  end

  it 'uses reported boot time for a later real reboot' do
    initial = evidence
    rebooted = evidence(
      boot_id: 'boot-b',
      booted_at: (t0 + 1.hour).iso8601
    )

    described_class.run(node:, observed_at: t0 + 10, report: report(initial))
    described_class.run(
      node:,
      observed_at: t0 + 1.hour + 10,
      report: report(rebooted),
      previous_report: report(initial),
      previous_observed_at: t0 + 10
    )

    boots = node.node_kernel_events.boot.order(:observed_before).to_a
    expect(boots.map(&:effective_at)).to eq([t0, t0 + 1.hour])
    expect(boots.map(&:boot_id)).to eq(%w[boot-a boot-b])
  end

  it 'reconciles a bootstrap event written by an old supervisor after migration' do
    reconstructed = NodeKernelEvent.create!(
      node:,
      event_type: :boot,
      source: :reconstructed_node_status,
      confidence: :inferred,
      booted_at: t0,
      booted_release: '6.12.93',
      reported_release: '6.12.93',
      effective_at: t0,
      observed_before: t0 + 60,
      current: false
    )
    bootstrap = NodeKernelEvent.create!(
      node:,
      event_type: :boot,
      source: :node_report,
      confidence: :inferred,
      boot_id: 'boot-a',
      booted_at: nil,
      booted_release: '6.12.93',
      reported_release: '6.12.93',
      observed_before: t0 + 90,
      current: true,
      kernel_evidence: event_snapshot(evidence)
    )
    current_report = report(evidence)

    queries = capture_sql do
      described_class.run(
        node:,
        observed_at: t0 + 120,
        report: current_report,
        previous_report: current_report,
        previous_observed_at: t0 + 90
      )
    end

    expect(bootstrap.reload).to be_exact
    expect(bootstrap.effective_at).to eq(t0)
    expect(NodeKernelEvent.exists?(reconstructed.id)).to be(false)
    expect(node.node_kernel_events.kernel_history.sole).to eq(bootstrap)
    expect(queries).to include(
      a_string_matching(/SELECT .*node_kernel_events.*FOR UPDATE/mi)
    )
  end

  it 'keeps bootstrap confidence tied to its immutable event evidence' do
    exact_snapshot = event_snapshot(evidence)
    bootstrap = NodeKernelEvent.create!(
      node:,
      event_type: :boot,
      source: :node_report,
      confidence: :inferred,
      boot_id: 'boot-a',
      booted_at: t0,
      booted_release: '6.12.93',
      reported_release: '6.12.93',
      observed_before: t0 + 90,
      current: true,
      kernel_evidence: exact_snapshot
    )
    later_fallback = report(evidence(errors: [{
      'component' => 'booted_at',
      'reason' => 'estimated_from_uptime'
    }]))

    described_class.run(
      node:,
      observed_at: t0 + 120,
      report: later_fallback,
      previous_report: later_fallback,
      previous_observed_at: t0 + 90
    )

    expect(bootstrap.reload).to be_exact
    expect(bootstrap.effective_at).to eq(exact_snapshot.booted_at)

    node.node_kernel_events.delete_all
    estimated_snapshot = event_snapshot(evidence(errors: [{
      'component' => 'booted_at',
      'reason' => 'estimated_from_uptime'
    }]))
    bootstrap = NodeKernelEvent.create!(
      node:,
      event_type: :boot,
      source: :node_report,
      confidence: :exact,
      boot_id: 'boot-a',
      booted_at: t0,
      booted_release: '6.12.93',
      reported_release: '6.12.93',
      observed_before: t0 + 90,
      current: true,
      kernel_evidence: estimated_snapshot
    )
    later_exact = report(evidence)

    described_class.run(
      node:,
      observed_at: t0 + 120,
      report: later_exact,
      previous_report: later_exact,
      previous_observed_at: t0 + 90
    )

    expect(bootstrap.reload).to be_inferred
    expect(bootstrap.effective_at).to eq(estimated_snapshot.booted_at)
  end

  it 'deletes at most one reconstructed boot per reported event' do
    reconstructed = 2.times.map do |index|
      NodeKernelEvent.create!(
        node:,
        event_type: :boot,
        source: :reconstructed_node_status,
        confidence: :inferred,
        booted_at: t0 + index.minutes,
        booted_release: '6.12.93',
        reported_release: '6.12.93',
        effective_at: t0 + index.minutes,
        observed_before: t0 + 60 + index.minutes,
        current: false
      )
    end
    bootstrap = NodeKernelEvent.create!(
      node:,
      event_type: :boot,
      source: :node_report,
      confidence: :inferred,
      boot_id: 'boot-a',
      booted_at: t0,
      booted_release: '6.12.93',
      reported_release: '6.12.93',
      observed_before: t0 + 90,
      current: true,
      kernel_evidence: event_snapshot(evidence)
    )
    current_report = report(evidence)

    2.times do |index|
      described_class.run(
        node:,
        observed_at: t0 + 120 + index.minutes,
        report: current_report,
        previous_report: current_report,
        previous_observed_at: t0 + 90 + index.minutes
      )
    end

    expect(NodeKernelEvent.exists?(reconstructed.first.id)).to be(false)
    expect(NodeKernelEvent.exists?(reconstructed.last.id)).to be(true)
    expect(node.node_kernel_events.kernel_history).to contain_exactly(
      bootstrap,
      reconstructed.last
    )
  end

  it 'repairs an actual reboot written by an old rolling-window supervisor' do
    rebooted_at = t0 + 1.hour
    reboot_report = evidence(
      boot_id: 'boot-b',
      booted_at: rebooted_at.iso8601
    )
    reconstructed = NodeKernelEvent.create!(
      node:,
      event_type: :boot,
      source: :reconstructed_node_status,
      confidence: :inferred,
      booted_at: rebooted_at,
      booted_release: '6.12.93',
      reported_release: '6.12.93',
      effective_at: rebooted_at,
      observed_before: rebooted_at + 5,
      current: false
    )
    reported = NodeKernelEvent.create!(
      node:,
      event_type: :boot,
      source: :node_report,
      confidence: :inferred,
      boot_id: 'boot-b',
      booted_at: rebooted_at,
      booted_release: '6.12.93',
      reported_release: '6.12.93',
      observed_after: t0 + 10,
      observed_before: rebooted_at + 10,
      current: true,
      kernel_evidence: event_snapshot(reboot_report, observed_at: rebooted_at + 10)
    )
    current_report = report(reboot_report)

    described_class.run(
      node:,
      observed_at: rebooted_at + 30,
      report: current_report,
      previous_report: current_report,
      previous_observed_at: rebooted_at + 10
    )

    expect(reported.reload).to be_exact
    expect(reported.effective_at).to eq(rebooted_at)
    expect(NodeKernelEvent.exists?(reconstructed.id)).to be(true)
    expect(node.node_kernel_events.kernel_history).to contain_exactly(reconstructed, reported)
  end
end
