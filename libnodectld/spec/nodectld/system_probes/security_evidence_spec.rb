# frozen_string_literal: true

require 'spec_helper'
require 'tempfile'
require 'nodectld/system_probes/security_evidence'

RSpec.describe NodeCtld::SystemProbes::SecurityEvidence do
  let(:now) { Time.utc(2026, 7, 1, 12, 0, 0) }

  it 'tokenizes the kernel command line without losing order or duplicate names' do
    probe = described_class.new
    probe.instance_variable_set(:@errors, [])

    expect(
      probe.send(:parse_command_line, 'foo=old quiet foo="new value" empty=""')
    ).to eq(['foo=old', 'quiet', 'foo=new value', 'empty='])

    expect(probe.send(:parse_command_line, 'foo="unterminated')).to eq([])
    expect(probe.instance_variable_get(:@errors)).to include(
      'component' => 'kernel.command_line',
      'reason' => 'invalid'
    )
  end

  it 'turns syntactically valid non-object metadata into an evidence gap' do
    probe = described_class.new
    probe.instance_variable_set(:@errors, [])

    ['[]', 'null', '42', '"text"'].each do |value|
      allow(File).to receive(:read).with('/tmp/metadata.json').and_return(value)
      expect(probe.send(:read_json, '/tmp/metadata.json')).to eq({})
    end
    expected_error = { 'component' => 'metadata', 'reason' => 'invalid' }
    expect(probe.instance_variable_get(:@errors)).to all(include(expected_error))
  end

  it 'uses the kernel text representation for configured sysctl scalars' do
    probe = described_class.new

    expect(
      [nil, true, false, 42, 'already-text'].map do |value|
        probe.send(:canonical_sysctl_value, value)
      end
    ).to eq([nil, '1', '0', '42', 'already-text'])
  end

  it 'falls back to the matching system closure confctl inputs' do
    revisions = {
      'vpsadminos' => 'a' * 40,
      'vpsadmin' => 'b' * 40,
      'nixpkgs' => 'c' * 40
    }
    os_metadata = {
      'version' => '26.05',
      'revision' => 'staging',
      'revisionDirty' => false,
      'nixpkgsVersion' => '26.11pre',
      'nixpkgsRevision' => nil
    }
    vpsadmin_metadata = {
      'version' => NodeCtld::VERSION,
      'revision' => 'dev',
      'revisionDirty' => false
    }
    inputs = revisions.to_h do |component, revision|
      [component, { 'rev' => revision }]
    end
    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:fetch).with('VPSADMIN_REVISION', nil).and_return(revisions['vpsadmin'])

    probe = described_class.new
    probe.instance_variable_set(:@errors, [])
    versions = probe.send(
      :booted_software_versions,
      os_metadata,
      vpsadmin_metadata,
      inputs
    ) + probe.send(:current_software_versions, os_metadata, vpsadmin_metadata, inputs)

    expect(versions.length).to eq(6)
    expect(versions).to all(
      include(
        'version_source' => 'native',
        'revision_source' => 'confctl',
        'revision_dirty' => false
      )
    )
    expect(versions.to_h { |version| [version['component'], version['revision']] }).to eq(revisions)
    expect(probe.instance_variable_get(:@errors)).to be_empty

    versions = probe.send(
      :booted_software_versions,
      os_metadata,
      {},
      inputs
    ) + probe.send(:current_software_versions, os_metadata, {}, inputs)
    vpsadmin_versions = versions.select { |version| version['component'] == 'vpsadmin' }
    expect(vpsadmin_versions).to all(
      include(
        'version' => nil,
        'version_source' => nil,
        'revision_source' => 'confctl'
      )
    )
    expect(probe.instance_variable_get(:@errors)).to be_empty
  end

  it 'does not treat a native revision with unknown dirty state as clean' do
    revision = 'd' * 40
    metadata = {
      'version' => '26.05',
      'revision' => revision
    }
    confctl_inputs = {
      'vpsadminos' => { 'rev' => 'e' * 40 }
    }
    probe = described_class.new
    probe.instance_variable_set(:@errors, [])

    fallback = probe.send(
      :software_version,
      'booted',
      'vpsadminos',
      metadata,
      confctl_inputs
    )
    expect(fallback).to include(
      'revision' => 'e' * 40,
      'revision_source' => 'confctl',
      'revision_dirty' => false
    )

    missing = probe.send(:software_version, 'booted', 'vpsadminos', metadata, {})
    expect(missing).to include(
      'revision' => nil,
      'revision_source' => nil,
      'revision_dirty' => false
    )
    expect(probe.instance_variable_get(:@errors)).to include(
      'component' => 'software.booted.vpsadminos.revision',
      'reason' => 'missing'
    )
  end

  it 'treats missing configuration metadata as optional and rejects malformed metadata' do
    probe = described_class.new
    probe.instance_variable_set(:@errors, [])
    allow(File).to receive(:read).with('/tmp/missing.json').and_raise(Errno::ENOENT)

    expect(
      probe.send(:read_configuration_info, '/tmp/missing.json', 'configuration')
    ).to be_nil
    expect(probe.instance_variable_get(:@errors)).to be_empty

    allow(File).to receive(:read).with('/tmp/invalid.json').and_return(
      JSON.generate(
        schemaVersion: 1,
        revision: 'staging',
        revisionDirty: false
      )
    )
    expect(
      probe.send(:read_configuration_info, '/tmp/invalid.json', 'configuration')
    ).to be_nil
    expect(probe.instance_variable_get(:@errors)).to contain_exactly(
      'component' => 'configuration',
      'reason' => 'invalid'
    )
  end

  it 'reports generic closure and runtime evidence without a CVE-specific allowlist' do
    vpsadminos_revision = 'a' * 40
    vpsadmin_revision = 'b' * 40
    nixpkgs_revision = 'c' * 40
    configuration_revision = 'd' * 40
    config = Tempfile.new('kernel-config')
    config_content = <<~CONFIG
      CONFIG_EXAMPLE_FUTURE_HARDENING=y
      # CONFIG_EXAMPLE_DISABLED is not set
    CONFIG
    config.write(config_content)
    config.flush

    metadata = {
      schemaVersion: 1,
      version: '25.11.1234.abcdef0',
      revision: vpsadminos_revision,
      revisionDirty: false,
      nixpkgsVersion: '26.05',
      nixpkgsRevision: nixpkgs_revision,
      kernelModDirVersion: '6.12.95',
      kernelSourceRevision: 'a2384967',
      kernelConfig: config.path
    }
    current_metadata = metadata.merge(
      sysctls: {
        'kernel.dmesg_restrict' => true,
        'vm.unprivileged_userfaultfd' => false
      }
    )
    vpsadmin_metadata = {
      schemaVersion: 1,
      version: NodeCtld::VERSION,
      revision: vpsadmin_revision,
      revisionDirty: false
    }
    livepatch = {
      kernelVersion: '6.12.93',
      module: 'livepatch_1',
      patchVersion: 1,
      patches: [{ name: 'fix-one', version: 1 }]
    }
    ebpf = {
      programs: [{
        name: 'guard',
        revision: 'vpsadminos-revision',
        digest: 'program-digest',
        bpfPrograms: ['guard_prog'],
        linkFields: ['guard_link']
      }]
    }
    allow(File).to receive(:read).and_call_original
    allow(File).to receive(:realpath).and_call_original
    allow(File).to receive(:read)
      .with(described_class::BOOTED_METADATA_PATH)
      .and_return(JSON.generate(metadata))
    allow(File).to receive(:read)
      .with(described_class::CURRENT_METADATA_PATH)
      .and_return(JSON.generate(current_metadata))
    allow(File).to receive(:read)
      .with(described_class::BOOTED_VPSADMIN_METADATA_PATH)
      .and_return(JSON.generate(vpsadmin_metadata))
    allow(File).to receive(:read)
      .with(described_class::CURRENT_VPSADMIN_METADATA_PATH)
      .and_return(JSON.generate(vpsadmin_metadata))
    allow(File).to receive(:read)
      .with(described_class::BOOTED_CONFIGURATION_INFO_PATH)
      .and_return(JSON.generate(
                    schemaVersion: 1,
                    revision: configuration_revision,
                    revisionDirty: false
                  ))
    allow(File).to receive(:read)
      .with(described_class::CURRENT_CONFIGURATION_INFO_PATH)
      .and_return(JSON.generate(
                    schemaVersion: 1,
                    revision: configuration_revision,
                    revisionDirty: true
                  ))
    allow(File).to receive(:realpath)
      .with(described_class::BOOTED_SYSTEM)
      .and_return('/nix/store/booted-vpsadminos-system')
    allow(File).to receive(:realpath)
      .with(described_class::CURRENT_SYSTEM)
      .and_return('/nix/store/current-vpsadminos-system')
    allow(File).to receive(:read).with(%r{\A/proc/sys/}).and_raise(Errno::ENOENT)
    allow(File).to receive(:read).with(described_class::BOOT_ID_PATH).and_return("boot-a\n")
    allow(File).to receive(:read).with(described_class::COMMAND_LINE_PATH)
                                 .and_return("init=\"/nix/store/init path\" debug=old debug=new slab_nomerge\n")
    allow(File).to receive(:read).with(described_class::BOOT_TIME_PATH).and_return("cpu 1 2 3\nbtime 1782903600\n")
    allow(File).to receive(:read).with(described_class::LIVEPATCH_MONITOR_PATH).and_return(JSON.generate(livepatch))
    allow(File).to receive(:read).with(described_class::EBPF_MONITOR_PATH).and_return(JSON.generate(ebpf))
    allow(File).to receive(:read)
      .with(File.join(described_class::EBPF_STATE_ROOT, 'current-generation'))
      .and_return("123-456\n")
    allow(File).to receive(:read)
      .with(File.join(described_class::EBPF_STATE_ROOT, '123-456.attached-at'))
      .and_return("2026-07-01T11:45:00Z\n")
    allow(File).to receive(:read).with('/sys/kernel/livepatch/livepatch_1/enabled').and_return("1\n")
    allow(File).to receive(:read).with('/sys/kernel/livepatch/livepatch_1/transition').and_return("0\n")
    allow(File).to receive(:read)
      .with(File.join(described_class::LIVEPATCH_STATE_ROOT, 'livepatch_1.applied-at'))
      .and_return("2026-07-01T11:30:00Z\n")
    allow(File).to receive(:read).with('/proc/sys/kernel/dmesg_restrict').and_return("1\n")
    allow(File).to receive(:read).with('/proc/sys/vm/unprivileged_userfaultfd').and_return("0\n")
    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:fetch).with('VPSADMIN_REVISION', nil).and_return(vpsadmin_revision)
    allow(File).to receive(:readlines).with(described_class::MODULES_PATH, chomp: true).and_return(
      [
        'kvm_amd 1 0 - Live 0x0',
        'kvm 1 1 kvm_amd, Live 0x0'
      ]
    )
    allow(Dir).to receive(:children).with(described_class::BOOTED_MODULES_PATH).and_return(['6.12.95'])
    allow(Dir).to receive(:exist?).with('/sys/module/livepatch_1').and_return(true)
    allow(Dir).to receive(:glob).and_return(['/sys/fs/bpf/vpsadminos/ebpf-livepatch/generations/1/guard__guard_link'])

    probe = described_class.new
    result = probe.values(now:, uptime: 600, reported_release: '6.12.93.1')

    expect(result['schema_version']).to eq(1)
    expect(result.dig('kernel', 'boot_id')).to eq('boot-a')
    expect(result.dig('kernel', 'booted_release')).to eq('6.12.95')
    expect(result.dig('kernel', 'reported_release')).to eq('6.12.93.1')
    expect(result.dig('kernel', 'config_digest')).to eq(Digest::SHA256.file(config.path).hexdigest)
    expect(result.dig('kernel', 'config_text')).to eq(config_content)
    expect(result.fetch('kernel')).not_to have_key('configured_params')
    expect(result.dig('kernel', 'booted_params')).to eq(
      ['init=/nix/store/init path', 'debug=old', 'debug=new', 'slab_nomerge']
    )
    expect(result.dig('kernel', 'command_line')).to eq(
      'init="/nix/store/init path" debug=old debug=new slab_nomerge'
    )
    expect(result.dig('livepatches', 0)).to include(
      'loaded' => true,
      'enabled' => true,
      'applied_at' => '2026-07-01T11:30:00Z'
    )
    expect(result.dig('ebpf_programs', 0, 'active')).to be(true)
    expect(result.dig('ebpf_programs', 0)).to include(
      'revision' => 'vpsadminos-revision',
      'digest' => 'program-digest',
      'attached_at' => '2026-07-01T11:45:00Z',
      'verified_at' => '2026-07-01T12:00:00Z'
    )
    expect(result['deployment']).to eq(
      'booted_system' => '/nix/store/booted-vpsadminos-system',
      'current_system' => '/nix/store/current-vpsadminos-system'
    )
    expect(result['loaded_modules']).to eq(%w[kvm kvm_amd])
    expect(result.dig('sysctls', 'kernel.dmesg_restrict')).to eq(
      'available' => true,
      'effective' => '1',
      'configured' => '1'
    )
    expect(result.fetch('sysctls')).not_to have_key('kernel.unprivileged_userns_clone')
    expect(result.fetch('software_versions')).to contain_exactly(
      {
        'generation' => 'booted',
        'component' => 'vpsadminos',
        'version' => '25.11.1234.abcdef0',
        'version_source' => 'native',
        'revision' => vpsadminos_revision,
        'revision_source' => 'native',
        'revision_dirty' => false
      },
      {
        'generation' => 'current',
        'component' => 'vpsadminos',
        'version' => '25.11.1234.abcdef0',
        'version_source' => 'native',
        'revision' => vpsadminos_revision,
        'revision_source' => 'native',
        'revision_dirty' => false
      },
      {
        'generation' => 'booted',
        'component' => 'vpsadmin',
        'version' => NodeCtld::VERSION,
        'version_source' => 'native',
        'revision' => vpsadmin_revision,
        'revision_source' => 'native',
        'revision_dirty' => false
      },
      {
        'generation' => 'current',
        'component' => 'vpsadmin',
        'version' => NodeCtld::VERSION,
        'version_source' => 'native',
        'revision' => vpsadmin_revision,
        'revision_source' => 'native',
        'revision_dirty' => false
      },
      {
        'generation' => 'booted',
        'component' => 'nixpkgs',
        'version' => '26.05',
        'version_source' => 'native',
        'revision' => nixpkgs_revision,
        'revision_source' => 'native',
        'revision_dirty' => false
      },
      {
        'generation' => 'current',
        'component' => 'nixpkgs',
        'version' => '26.05',
        'version_source' => 'native',
        'revision' => nixpkgs_revision,
        'revision_source' => 'native',
        'revision_dirty' => false
      },
      {
        'generation' => 'booted',
        'component' => 'vpsfree_cz_configuration',
        'version' => nil,
        'version_source' => nil,
        'revision' => configuration_revision,
        'revision_source' => 'native',
        'revision_dirty' => false
      },
      {
        'generation' => 'current',
        'component' => 'vpsfree_cz_configuration',
        'version' => nil,
        'version_source' => nil,
        'revision' => configuration_revision,
        'revision_source' => 'native',
        'revision_dirty' => true
      }
    )
    expect(result['errors']).to be_empty

    probe.report_published
    repeated = probe.values(now: now + 60, uptime: 660, reported_release: '6.12.93.1')
    expect(repeated['kernel']).not_to have_key('config_text')

    periodic = probe.values(
      now: now + described_class::KERNEL_CONFIG_REPORT_INTERVAL,
      uptime: 600 + described_class::KERNEL_CONFIG_REPORT_INTERVAL,
      reported_release: '6.12.93.1'
    )
    expect(periodic.dig('kernel', 'config_text')).to eq(config_content)
    expect(File).to have_received(:read).with(config.path).once
    expect(File).to have_received(:read).with(described_class::BOOTED_METADATA_PATH).once
    expect(File).to have_received(:read).with(described_class::BOOTED_VPSADMIN_METADATA_PATH).once
    expect(File).to have_received(:read).with(described_class::BOOT_ID_PATH).once
    expect(File).to have_received(:read).with(described_class::COMMAND_LINE_PATH).once
    expect(File).to have_received(:read).with(described_class::BOOT_TIME_PATH).once
    expect(Dir).to have_received(:children).with(described_class::BOOTED_MODULES_PATH).once
    expect(File).to have_received(:realpath).with(described_class::BOOTED_SYSTEM).once
    expect(File).to have_received(:read).with(described_class::CURRENT_METADATA_PATH).exactly(3).times
    expect(File).to have_received(:read)
      .with(described_class::CURRENT_VPSADMIN_METADATA_PATH)
      .exactly(3).times
    expect(File).to have_received(:realpath).with(described_class::CURRENT_SYSTEM).exactly(3).times

    legacy_metadata = metadata.except(:schemaVersion)
    allow(File).to receive(:read)
      .with(described_class::BOOTED_METADATA_PATH)
      .and_return(JSON.generate(legacy_metadata))
    legacy_boot = described_class.new.values(now:, uptime: 600, reported_release: '6.12.93.1')
    expect(legacy_boot.fetch('kernel')).not_to have_key('configured_params')
    expect(legacy_boot['errors']).to include(
      'component' => 'booted_metadata',
      'reason' => 'supported metadata is unavailable'
    )

    allow(File).to receive(:realpath).with(described_class::CURRENT_SYSTEM).and_raise(Errno::ENOENT)
    missing_current_system = described_class.new.values(now:, uptime: 600, reported_release: '6.12.93.1')
    expect(missing_current_system.dig('deployment', 'current_system')).to be_nil
    expect(missing_current_system['errors']).to include(
      'component' => 'current_system',
      'reason' => 'unavailable'
    )

    allow(Dir).to receive(:glob).and_return([])
    inactive = described_class.new.values(now:, uptime: 600, reported_release: '6.12.93.1')
    expect(inactive['errors']).not_to include(
      'component' => 'ebpf_attached_at',
      'reason' => 'unavailable'
    )
  ensure
    config&.close!
  end
end
