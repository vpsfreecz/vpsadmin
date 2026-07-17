# frozen_string_literal: true

require 'spec_helper'

RSpec.describe NodeKernelEvidence do
  let(:node) { SpecSeed.node }
  let(:observed_at) { Time.utc(2026, 7, 14, 12, 0, 0) }

  def report
    {
      'schema_version' => 1,
      'kernel' => {
        'boot_id' => 'boot-a',
        'booted_at' => (observed_at - 1.hour).iso8601,
        'booted_release' => '6.12.95',
        'reported_release' => '6.12.95',
        'kernel_source_revision' => 'linux-revision',
        'config_digest' => 'a' * 64,
        'booted_params' => ['debug=old', 'debug=new', 'slab_nomerge'],
        'command_line' => 'slab_nomerge debug debug= debug=one=two debug'
      },
      'livepatches' => [{
        'id' => 'fix-cve',
        'kernel_version' => nil,
        'patch_version' => 2,
        'loaded' => nil,
        'enabled' => true,
        'transition' => nil,
        'applied_at' => nil,
        'verified_at' => nil,
        'patches' => [{ 'name' => 'fix_target', 'version' => 2 }]
      }],
      'ebpf_programs' => [{
        'name' => 'security-hook',
        'description' => nil,
        'sinceKernel' => nil,
        'untilKernel' => nil,
        'revision' => nil,
        'digest' => nil,
        'active' => true,
        'attached_at' => nil,
        'verified_at' => nil,
        'bpfPrograms' => ['lsm_hook'],
        'links' => { 'lsm/file_open' => true }
      }],
      'loaded_modules' => ['kvm'],
      'software_versions' => %w[booted current].product(
        %w[vpsadminos vpsadmin nixpkgs]
      ).map do |generation, component|
        {
          'generation' => generation,
          'component' => component,
          'version' => "#{component}-version",
          'version_source' => 'native',
          'revision' => Digest::SHA1.hexdigest("#{generation}.#{component}"),
          'revision_source' => 'native',
          'revision_dirty' => false
        }
      end,
      'sysctls' => {
        'kernel.dmesg_restrict' => {
          'available' => true,
          'configured' => 1,
          'effective' => '1'
        }
      },
      'deployment' => {
        'booted_system' => '/nix/store/booted',
        'current_system' => '/nix/store/current'
      },
      'errors' => []
    }
  end

  def normalize(value)
    VpsAdmin::API::KernelEvidence::Report.from_hash(value)
  end

  def write(snapshot, value, received_at: observed_at)
    VpsAdmin::API::KernelEvidence::SnapshotWriter.call(
      snapshot:,
      report: normalize(value),
      observed_at:,
      received_at:
    )
  end

  def read(snapshot)
    VpsAdmin::API::KernelEvidence::SnapshotReader.call(snapshot)
  end

  it 'rejects alternate internal report shapes instead of normalizing them' do
    scalar_sysctl = report.deep_dup
    scalar_sysctl['sysctls']['kernel.dmesg_restrict'] = '1'
    expect { normalize(scalar_sysctl) }
      .to raise_error(TypeError, /sysctls\.kernel\.dmesg_restrict must be an object/)

    missing_source = report.deep_dup
    missing_source.fetch('software_versions').first.delete('revision_source')
    expect { normalize(missing_source) }.to raise_error(KeyError, /revision_source/)

    non_string_parameter = report.deep_dup
    non_string_parameter.fetch('kernel')['booted_params'] = [1]
    expect { normalize(non_string_parameter) }
      .to raise_error(TypeError, /kernel\.booted_params entries must be strings/)
  end

  it 'normalizes a report into independently queryable relational rows' do
    evidence = described_class.new(node:, snapshot_type: :current)
    write(evidence, report)

    expect(
      evidence.kernel_parameters.order(:position).pluck(:position, :name, :value)
    ).to eq(
      [
        [0, 'debug', 'old'],
        [1, 'debug', 'new'],
        [2, 'slab_nomerge', nil]
      ]
    )
    expect(evidence.kernel_modules.pluck(:name)).to eq(['kvm'])
    expect(evidence.sysctls.pluck(:name, :available, :effective_value)).to eq(
      [['kernel.dmesg_restrict', true, '1']]
    )
    expect(evidence.software_versions.count).to eq(6)
    expect(evidence.kernel_livepatches.sole.patches.pluck(:name, :version)).to eq(
      [%w[fix_target 2]]
    )
    expect(evidence.ebpf_programs.sole.program_links.pluck(:name, :attached)).to eq(
      [['lsm/file_open', true]]
    )
    expect(read(evidence)).to eq(normalize(report))
    expect(evidence.snapshot_revision).to eq(normalize(report).digest)
  end

  it 'does not replace an immutable event snapshot' do
    evidence = described_class.new(node:, snapshot_type: :event)
    write(evidence, report)

    expect do
      write(evidence, report, received_at: observed_at + 1.minute)
    end.to raise_error(ActiveRecord::ReadOnlyRecord)
  end

  it 'normalizes set-like report data without collapsing ordered parameters' do
    duplicate_report = report
    booted_params = duplicate_report['kernel']['booted_params'].dup
    duplicate_report['kernel']['booted_params'] *= 2
    duplicate_report['loaded_modules'] *= 2
    newer_livepatch = duplicate_report['livepatches'][0].deep_dup
    newer_livepatch['patch_version'] = 3
    newer_livepatch['patches'] << { 'name' => 'fix_target', 'version' => 3 }
    duplicate_report['livepatches'] << newer_livepatch
    newer_program = duplicate_report['ebpf_programs'][0].deep_dup
    newer_program['digest'] = 'new-digest'
    newer_program['bpfPrograms'] *= 2
    duplicate_report['ebpf_programs'] << newer_program
    normalized = normalize(duplicate_report)

    evidence = described_class.new(node:, snapshot_type: :current)
    write(evidence, duplicate_report)

    expect(read(evidence)).to eq(normalized)
    expect(normalized.to_h.dig('kernel', 'booted_params')).to eq(
      booted_params * 2
    )
    expect(normalized.loaded_modules).to eq(['kvm'])
    expect(normalized.to_h.dig('livepatches', 0, 'patch_version')).to eq('3')
    expect(normalized.to_h.dig('livepatches', 0, 'patches')).to eq(
      [{ 'name' => 'fix_target', 'version' => '3' }]
    )
    expect(normalized.to_h.dig('ebpf_programs', 0, 'digest')).to eq('new-digest')
    expect(normalized.to_h.dig('ebpf_programs', 0, 'bpfPrograms')).to eq(['lsm_hook'])
    expect(evidence.snapshot_revision).to eq(normalized.digest)
  end

  it 'treats parameter reordering as a different snapshot' do
    original = normalize(report)
    reordered = normalize(report.deep_dup.tap do |copy|
      copy['kernel']['booted_params'].reverse!
    end)

    expect(reordered.digest).not_to eq(original.digest)
  end

  it 'preserves case-distinct kernel module names' do
    case_sensitive_report = report
    case_sensitive_report['loaded_modules'] = %w[xt_DSCP xt_dscp xt_TCPMSS xt_tcpmss]

    evidence = described_class.new(node:, snapshot_type: :current)
    write(evidence, case_sensitive_report)

    expect(evidence.kernel_modules.order(:name).pluck(:name)).to contain_exactly(
      'xt_DSCP',
      'xt_dscp',
      'xt_TCPMSS',
      'xt_tcpmss'
    )
    expect(read(evidence).loaded_modules).to contain_exactly(
      'xt_DSCP',
      'xt_dscp',
      'xt_TCPMSS',
      'xt_tcpmss'
    )
  end
end
