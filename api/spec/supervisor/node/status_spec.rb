# frozen_string_literal: true

require 'spec_helper'

RSpec.describe VpsAdmin::Supervisor::Node::Status do
  let(:node) { SpecSeed.node }
  let(:supervisor) { described_class.new(nil, node) }
  let(:timestamp) { Time.utc(2026, 4, 5, 12, 0, 0) }
  let(:now) { Time.utc(2026, 4, 5, 12, 30, 0) }

  def payload(overrides = {})
    {
      'id' => node.id,
      'time' => timestamp.to_i,
      'uptime' => 3600,
      'nproc' => 42,
      'loadavg' => { '1' => 0.5, '5' => 0.25, '15' => 0.1 },
      'vpsadmin_version' => 'spec',
      'kernel' => '6.8.0',
      'cgroup_version' => NodeCurrentStatus.cgroup_versions[:cgroup_v2],
      'cpus' => 8,
      'cpu' => {
        'user' => 10.0,
        'nice' => 0.0,
        'system' => 5.0,
        'idle' => 80.0,
        'iowait' => 2.0,
        'irq' => 1.0,
        'softirq' => 1.0,
        'guest' => 0.0
      },
      'memory' => { 'total' => 8 * 1024 * 1024, 'used' => 4 * 1024 * 1024 },
      'swap' => { 'total' => 2 * 1024 * 1024, 'used' => 1 * 1024 * 1024 },
      'storage' => {
        'state' => 'online',
        'scan' => 'none',
        'scan_percent' => nil,
        'checked_at' => timestamp.to_i
      },
      'arc' => {
        'c_max' => 512 * 1024 * 1024,
        'c' => 256 * 1024 * 1024,
        'size' => 128 * 1024 * 1024,
        'hitpercent' => 95.5
      }
    }.merge(overrides)
  end

  def evidence
    config_text = "CONFIG_IPV6=y\n"
    sysctls = %w[kernel.dmesg_restrict vm.unprivileged_userfaultfd].to_h do |name|
      [
        name,
        {
          'available' => true,
          'configured' => 1,
          'effective' => '1'
        }
      ]
    end
    {
      'schema_version' => 1,
      'kernel' => {
        'boot_id' => 'boot-v2',
        'booted_at' => (timestamp - 3600).iso8601,
        'booted_release' => '6.8.0',
        'reported_release' => '6.8.0',
        'kernel_source_revision' => 'kernel-revision',
        'config_digest' => Digest::SHA256.hexdigest(config_text),
        'config_text' => config_text,
        'booted_params' => ['debug=old', 'debug=new'],
        'command_line' => 'debug=old debug=new'
      },
      'livepatches' => [],
      'ebpf_programs' => [],
      'loaded_modules' => [],
      'sysctls' => sysctls,
      'deployment' => {
        'booted_system' => '/nix/store/booted-system',
        'current_system' => '/nix/store/current-system'
      },
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
      'errors' => []
    }
  end

  before do
    allow(Time).to receive(:now).and_return(now)
  end

  def stored_report(current)
    snapshot = current.reload.kernel_evidence
    VpsAdmin::API::KernelEvidence::SnapshotReader.call(snapshot)&.to_h
  end

  def parse_evidence(value)
    VpsAdmin::API::KernelEvidence::PayloadParser.call(value)
  end

  describe '#start' do
    it 'ignores payloads for other nodes' do
      channel = SupervisorConsumerHelpers::FakeSupervisorChannel.new
      described_class.new(channel, node).start

      queue = channel.queues.fetch("node:#{node.domain_name}:statuses")
      queue.publish(payload('id' => node.id + 10_000).to_json)

      expect(NodeCurrentStatus.where(node:)).not_to exist
    end
  end

  describe '#update_status' do
    it 'stores current status values in MiB and logs the first sample' do
      current = NodeCurrentStatus.find_or_initialize_by(node:)

      supervisor.send(:update_status, current, payload)

      current.reload
      expect(current.uptime).to eq(3600)
      expect(current.process_count).to eq(42)
      expect(current.total_memory).to eq(8192)
      expect(current.used_memory).to eq(4096)
      expect(current.total_swap).to eq(2048)
      expect(current.used_swap).to eq(1024)
      expect(current.arc_c_max).to eq(512)
      expect(current.arc_c).to eq(256)
      expect(current.arc_size).to eq(128)
      expect(current.arc_hitpercent).to eq(95.5)
      expect(current.pool_state).to eq('online')
      expect(current.pool_scan).to eq('none')
      expect(current.pool_checked_at).to eq(timestamp)
      expect(current.last_log_at).to eq(now)
      expect(current.update_count).to eq(1)

      log = NodeStatus.find_by!(node:)
      expect(log.created_at).to eq(timestamp)
      expect(log.process_count).to eq(42)
      expect(log.used_memory).to eq(4096)
    end

    it 'updates the authoritative system-state timeline' do
      current = NodeCurrentStatus.find_or_initialize_by(node:)

      supervisor.send(:update_status, current, payload)

      state = node.node_system_states.sole
      expect(state).to have_attributes(
        cpus: 8,
        total_memory: 8192,
        total_swap: 2048,
        cgroup_version: 'cgroup_v2',
        first_observed_at: timestamp,
        last_observed_at: timestamp,
        current: true
      )
      supervisor.send(
        :update_status,
        current.reload,
        payload('time' => (timestamp + 60).to_i)
      )

      expect(node.node_system_states.count).to eq(1)
      expect(state.reload.last_observed_at).to eq(timestamp + 60)

      supervisor.send(
        :update_status,
        current.reload,
        payload(
          'time' => (timestamp + 120).to_i,
          'cpus' => 16,
          'memory' => { 'total' => 16 * 1024 * 1024, 'used' => 4 * 1024 * 1024 },
          'swap' => { 'total' => 0, 'used' => 0 },
          'cgroup_version' => NodeCurrentStatus.cgroup_versions[:cgroup_v1]
        )
      )

      states = node.node_system_states.order(:first_observed_at).to_a
      expect(states.length).to eq(2)
      expect(states.first).not_to be_current
      expect(states.last).to have_attributes(
        cpus: 16,
        total_memory: 16_384,
        total_swap: 0,
        cgroup_version: 'cgroup_v1',
        current: true
      )
    end

    it 'updates the legacy rollback cache from the current report' do
      current = NodeCurrentStatus.find_or_initialize_by(node:)

      supervisor.send(:update_status, current, payload)

      expect(node.reload.attributes.symbolize_keys).to include(
        cpus: 8,
        total_memory: 8192,
        total_swap: 2048
      )
      expect(node).to have_attributes(cpus: 8, total_memory: 8192, total_swap: 2048)
    end

    it 'rolls back current status when state recording fails' do
      current = NodeCurrentStatus.find_or_initialize_by(node:)
      cache_before = node.attributes.slice('cpus', 'total_memory', 'total_swap')
      allow(VpsAdmin::API::SystemState::Recorder)
        .to receive(:call)
        .and_raise(ActiveRecord::RecordInvalid)

      expect do
        supervisor.send(:update_status, current, payload)
      end.to raise_error(ActiveRecord::RecordInvalid)

      expect(NodeCurrentStatus.where(node:)).not_to exist
      expect(node.reload.attributes.slice('cpus', 'total_memory', 'total_swap')).to eq(cache_before)
      expect(node.node_system_states).to be_empty
    end

    it 'records impossible CPU and memory capacities as unknown' do
      current = NodeCurrentStatus.find_or_initialize_by(node:)

      supervisor.send(
        :update_status,
        current,
        payload(
          'cpus' => 0,
          'memory' => { 'total' => 0, 'used' => 0 },
          'swap' => { 'total' => 0, 'used' => 0 }
        )
      )

      expect(node.node_system_states.sole).to have_attributes(
        cpus: nil,
        total_memory: nil,
        total_swap: 0
      )
      expect(node.reload.attributes.symbolize_keys).to include(
        cpus: 0,
        total_memory: 0,
        total_swap: 0
      )
      expect(node).to have_attributes(cpus: nil, total_memory: nil, total_swap: 0)
    end

    it 'clears ARC values when the payload omits ARC data' do
      current = NodeCurrentStatus.find_or_initialize_by(node:)
      supervisor.send(:update_status, current, payload)

      current.reload
      supervisor.send(:update_status, current, payload('arc' => nil))

      current.reload
      expect(current.arc_c_max).to be_nil
      expect(current.arc_c).to be_nil
      expect(current.arc_size).to be_nil
      expect(current.arc_hitpercent).to be_nil
    end

    it 'resets invalid rolling average state before logging' do
      current = NodeCurrentStatus.create!(
        node:,
        created_at: timestamp - 60,
        updated_at: timestamp - 60,
        kernel: 'devcluster',
        vpsadmin_version: 'dev',
        update_count: 0
      )

      expect do
        supervisor.send(:update_status, current, payload)
      end.not_to raise_error

      current.reload
      expect(current.kernel).to eq('6.8.0')
      expect(current.update_count).to eq(1)
      expect(current.sum_loadavg1).to eq(0.5)

      log = NodeStatus.find_by!(node:)
      expect(log.loadavg1).to eq(0.5)
    end

    it 'updates rolling sums and update count between log intervals' do
      current = NodeCurrentStatus.find_or_initialize_by(node:)
      supervisor.send(:update_status, current, payload)

      current.reload
      next_sample = payload(
        'time' => (timestamp + 60).to_i,
        'nproc' => 58,
        'memory' => { 'total' => 8 * 1024 * 1024, 'used' => 5 * 1024 * 1024 },
        'swap' => { 'total' => 2 * 1024 * 1024, 'used' => 512 * 1024 },
        'cpu' => payload.fetch('cpu').merge('user' => 12.0)
      )

      supervisor.send(:update_status, current, next_sample)

      current.reload
      expect(current.update_count).to eq(2)
      expect(current.sum_process_count).to eq(100)
      expect(current.sum_used_memory).to eq(9216)
      expect(current.sum_used_swap).to eq(1536)
      expect(current.sum_cpu_user).to eq(22.0)
      expect(NodeStatus.where(node:).count).to eq(1)
    end

    it 'stores unsupported security evidence as an explicit current gap' do
      current = NodeCurrentStatus.find_or_initialize_by(node:)

      expect do
        supervisor.send(
          :update_status,
          current,
          payload('security_evidence' => { 'schema_version' => 2 })
        )
      end.not_to raise_error

      expect(current.reload.kernel).to eq('6.8.0')
      expect(stored_report(current).fetch('schema_version')).to eq(2)
      expect(stored_report(current).dig('errors', 0, 'reason'))
        .to include('unsupported schema version 2')
      expect(node.node_kernel_events).to be_empty
    end

    it 'replaces previously valid evidence when a current schema is unsupported' do
      current = NodeCurrentStatus.find_or_initialize_by(node:)
      supervisor.send(:update_status, current, payload('security_evidence' => evidence))
      event_ids = node.node_kernel_events.ids

      supervisor.send(
        :update_status,
        current,
        payload(
          'time' => (timestamp + 60).to_i,
          'security_evidence' => { 'schema_version' => 2 }
        )
      )

      current.reload
      expect(stored_report(current).fetch('schema_version')).to eq(2)
      expect(stored_report(current).dig('errors', 0, 'reason'))
        .to include('unsupported schema version 2')
      expect(stored_report(current).dig('kernel', 'booted_release')).to be_nil
      expect(node.node_kernel_events.ids).to eq(event_ids)
    end

    it 'stores the current software, boot parameter and sysctl evidence' do
      current = NodeCurrentStatus.find_or_initialize_by(node:)

      supervisor.send(
        :update_status,
        current,
        payload('security_evidence' => evidence)
      )

      report = stored_report(current)
      expect(report.fetch('schema_version')).to eq(1)
      expect(report.dig('kernel', 'booted_params')).to eq(['debug=old', 'debug=new'])
      expect(report.fetch('software_versions').length).to eq(6)
      expect(report.fetch('sysctls').keys).to contain_exactly(
        'kernel.dmesg_restrict',
        'vm.unprivileged_userfaultfd'
      )
      expect(current.kernel_evidence.software_versions.count).to eq(6)
      expect(current.kernel_evidence.kernel_parameters.count).to eq(2)
      expect(node.node_kernel_events.boot.sole.software_changes.count).to eq(6)
    end

    it 'normalizes legacy configuration provenance independently for each closure' do
      current = NodeCurrentStatus.find_or_initialize_by(node:)
      value = evidence
      value.fetch('software_versions') << {
        'generation' => 'current',
        'component' => 'vpsfree_cz_configuration',
        'version' => nil,
        'version_source' => nil,
        'revision' => 'd' * 40,
        'revision_source' => 'native',
        'revision_dirty' => true
      }

      supervisor.send(
        :update_status,
        current,
        payload('security_evidence' => value)
      )

      configuration = current.reload.kernel_evidence.software_versions.find_by!(
        generation: :current,
        component: :system_configuration
      )
      expect(configuration).to have_attributes(
        revision: 'd' * 40,
        revision_source: 'native',
        revision_dirty: true
      )
      expect(configuration.component_before_type_cast).to eq(3)
      expect(NodeSoftwareVersion.components.fetch('system_configuration')).to eq(3)
      expect(NodeSoftwareChange.components.fetch('system_configuration')).to eq(3)
      expect(current.kernel_evidence.software_versions.count).to eq(7)
      expect(
        node.node_kernel_events.boot.sole.software_changes
            .find_by!(generation: :current, component: :system_configuration)
            .after_revision
      ).to eq('d' * 40)
    end

    it 'rejects duplicate legacy and generic configuration identities' do
      value = evidence
      configuration = {
        'generation' => 'current',
        'component' => 'system_configuration',
        'version' => nil,
        'version_source' => nil,
        'revision' => 'd' * 40,
        'revision_source' => 'native',
        'revision_dirty' => false
      }
      value.fetch('software_versions') << configuration
      value.fetch('software_versions') << configuration.merge(
        'component' => 'vpsfree_cz_configuration'
      )

      expect(parse_evidence(value).record_events).to be(false)
    end

    it 'rejects non-scalar sysctl values and non-string eBPF metadata' do
      cases = [
        evidence.tap do |evidence|
          evidence.fetch('sysctls').values.first['configured'] = []
        end,
        evidence.tap do |evidence|
          evidence['ebpf_programs'] = [{
            'name' => 'guard',
            'description' => {},
            'revision' => 'revision',
            'digest' => 'digest',
            'active' => false,
            'bpfPrograms' => [],
            'links' => {},
            'attached_at' => nil,
            'verified_at' => nil
          }]
        end
      ]

      cases.each do |evidence|
        result = parse_evidence(evidence)

        expect(result.record_events).to be(false)
        expect(result.report.errors.sole.reason).to start_with('invalid:')
      end
    end

    it 'accepts any well-formed sysctl inventory' do
      value = evidence
      value['sysctls'] = {
        'net.ipv4.ip_forward' => {
          'available' => true,
          'configured' => false,
          'effective' => '0'
        }
      }

      result = parse_evidence(value)

      expect(result.record_events).to be(true)
      expect(result.report.sysctls.keys).to eq(['net.ipv4.ip_forward'])
      expect(result.report.sysctls.fetch('net.ipv4.ip_forward').configured).to eq('false')
    end

    it 'rejects incomplete or malformed current contracts' do
      cases = [
        evidence.tap { |value| value.delete('sysctls') },
        evidence.tap do |value|
          value['sysctls'] = {
            'invalid' => {
              'available' => true,
              'configured' => 1,
              'effective' => '1'
            }
          }
        end,
        evidence.tap do |value|
          value.fetch('software_versions').first['revision'] = ''
        end,
        evidence.tap do |value|
          value.fetch('software_versions') << value.fetch('software_versions').first.dup
        end,
        evidence.tap do |value|
          value.fetch('software_versions') << {
            'generation' => 'current',
            'component' => 'unknown',
            'version' => nil,
            'version_source' => nil,
            'revision' => 'd' * 40,
            'revision_source' => 'native',
            'revision_dirty' => false
          }
        end
      ]

      cases.each do |evidence|
        expect(parse_evidence(evidence).record_events).to be(false)
      end
    end

    it 'rejects invalid revision provenance' do
      cases = [
        evidence.tap do |value|
          value.fetch('software_versions').first['revision'] = 'staging'
        end,
        evidence.tap do |value|
          value.fetch('software_versions').first['revision_source'] = nil
        end,
        evidence.tap do |value|
          version = value.fetch('software_versions').first
          version['revision_source'] = 'confctl'
          version['revision_dirty'] = true
        end
      ]

      cases.each do |evidence|
        expect(parse_evidence(evidence).record_events).to be(false)
      end
    end

    it 'accepts a revision-only confctl fallback identity' do
      evidence = evidence()
      version = evidence.fetch('software_versions').find do |item|
        item['generation'] == 'booted' && item['component'] == 'vpsadmin'
      end
      version['version'] = nil
      version['version_source'] = nil
      version['revision_source'] = 'confctl'

      expect(parse_evidence(evidence).record_events).to be(true)
    end

    it 'deduplicates full kernel configurations outside status evidence' do
      current = NodeCurrentStatus.find_or_initialize_by(node:)
      config_text = "CONFIG_IPV6=y\n# CONFIG_KVM is not set\n"
      digest = Digest::SHA256.hexdigest(config_text)
      evidence = evidence()
      evidence.fetch('kernel').merge!(
        'config_digest' => digest,
        'config_text' => config_text,
        'booted_params' => ['slab_nomerge'],
        'command_line' => 'slab_nomerge'
      )

      supervisor.send(:update_status, current, payload('security_evidence' => evidence))

      stored = stored_report(current)
      expect(stored['kernel']).not_to have_key('config_text')
      expect(stored.dig('kernel', 'config_digest')).to eq(digest)
      configuration = NodeKernelConfiguration.find_by!(digest:)
      expect(configuration.content).to eq(config_text)
      expect(configuration.kernel_configuration_options.pluck(:name, :value).to_h).to eq(
        'CONFIG_IPV6' => 'y',
        'CONFIG_KVM' => 'n'
      )
      expect(
        VpsAdmin::API::KernelEvidence::SnapshotReader.call(
          node.node_kernel_events.first.kernel_evidence
        ).to_h['kernel']
      )
        .not_to have_key('config_text')

      supervisor.send(:update_status, current, payload('security_evidence' => evidence))
      expect(NodeKernelConfiguration.where(digest:).count).to eq(1)
      expect(node.node_kernel_events.count).to eq(1)
    end

    it 'rejects kernel configuration content whose digest does not match' do
      current = NodeCurrentStatus.find_or_initialize_by(node:)
      evidence = evidence()
      evidence.fetch('kernel').merge!(
        'config_digest' => 'a' * 64,
        'config_text' => "CONFIG_IPV6=y\n"
      )

      supervisor.send(:update_status, current, payload('security_evidence' => evidence))

      expect(stored_report(current).dig('errors', 0, 'reason'))
        .to include('does not match config_digest')
      expect(NodeKernelConfiguration.count).to eq(0)
      expect(node.node_kernel_events).to be_empty
    end

    it 'rejects incomplete current evidence without losing ordinary status' do
      current = NodeCurrentStatus.find_or_initialize_by(node:)
      evidence = evidence()
      evidence.fetch('kernel').delete('command_line')

      supervisor.send(:update_status, current, payload('security_evidence' => evidence))

      expect(current.reload.kernel).to eq('6.8.0')
      expect(stored_report(current).dig('errors', 0, 'reason')).to include('command_line')
      expect(node.node_kernel_events).to be_empty
    end

    it 'turns malformed nested mitigation evidence into a per-node gap' do
      current = NodeCurrentStatus.find_or_initialize_by(node:)
      evidence = evidence()
      evidence['ebpf_programs'] = [{
        'name' => 'guard',
        'revision' => 'revision',
        'digest' => 'digest',
        'active' => true,
        'bpfPrograms' => ['guard_entry'],
        'links' => { 'lsm/file_open' => false },
        'attached_at' => timestamp.iso8601,
        'verified_at' => timestamp.iso8601
      }]

      supervisor.send(:update_status, current, payload('security_evidence' => evidence))

      current.reload
      expect(stored_report(current).dig('errors', 0, 'reason'))
        .to include('active must equal the state of all links')
      expect(node.node_kernel_events).to be_empty
    end

    it 'recovers from malformed evidence without recording a false reboot' do
      current = NodeCurrentStatus.find_or_initialize_by(node:)
      supervisor.send(
        :update_status,
        current,
        payload('security_evidence' => evidence)
      )

      malformed = evidence
      malformed.fetch('sysctls').values.first['configured'] = []
      supervisor.send(
        :update_status,
        current,
        payload(
          'time' => (timestamp + 60).to_i,
          'security_evidence' => malformed
        )
      )
      expect(stored_report(current).dig('errors', 0, 'reason')).to start_with('invalid:')

      supervisor.send(
        :update_status,
        current,
        payload(
          'time' => (timestamp + 120).to_i,
          'security_evidence' => evidence
        )
      )

      expect(node.node_kernel_events.boot.count).to eq(1)
      expect(node.node_kernel_events.count).to eq(1)
      expect(stored_report(current).fetch('errors')).to be_empty
    end

    it 'accepts an inactive eBPF program with no kernel links' do
      current = NodeCurrentStatus.find_or_initialize_by(node:)
      evidence = evidence()
      evidence['ebpf_programs'] = [{
        'name' => 'guard',
        'revision' => 'revision',
        'digest' => 'digest',
        'active' => false,
        'bpfPrograms' => [],
        'links' => {},
        'attached_at' => nil,
        'verified_at' => nil
      }]

      supervisor.send(:update_status, current, payload('security_evidence' => evidence))

      expect(stored_report(current).fetch('errors')).to be_empty
      expect(stored_report(current).dig('ebpf_programs', 0, 'active')).to be(false)
    end

    it 'accepts duplicate booted parameters in their original order' do
      current = NodeCurrentStatus.find_or_initialize_by(node:)
      evidence = evidence()
      parameters = ['debug', 'debug=', 'debug=one=two', 'debug']
      evidence['kernel']['booted_params'] = parameters

      supervisor.send(:update_status, current, payload('security_evidence' => evidence))

      expect(stored_report(current).dig('kernel', 'booted_params')).to eq(parameters)
    end

    it 'rejects duplicate keys in set-like relational components' do
      livepatch = {
        'id' => 'fix-cve',
        'kernel_version' => '6.8.0',
        'patch_version' => 1,
        'loaded' => true,
        'enabled' => true,
        'transition' => false,
        'patches' => [{ 'name' => 'fix_target', 'version' => 1 }]
      }
      program = {
        'name' => 'guard',
        'revision' => 'revision',
        'digest' => 'digest',
        'active' => false,
        'bpfPrograms' => ['guard_entry'],
        'links' => {},
        'attached_at' => nil,
        'verified_at' => nil
      }
      cases = {
        'loaded_modules' => lambda do |evidence|
          evidence['loaded_modules'] = %w[kvm kvm]
        end,
        'livepatches' => lambda do |evidence|
          evidence['livepatches'] = [livepatch.deep_dup, livepatch.deep_dup]
        end,
        'livepatch.patches' => lambda do |evidence|
          evidence['livepatches'] = [livepatch.deep_dup]
          evidence['livepatches'][0]['patches'] *= 2
        end,
        'ebpf_programs' => lambda do |evidence|
          evidence['ebpf_programs'] = [program.deep_dup, program.deep_dup]
        end,
        'eBPF program.bpfPrograms' => lambda do |evidence|
          evidence['ebpf_programs'] = [program.deep_dup]
          evidence['ebpf_programs'][0]['bpfPrograms'] *= 2
        end
      }
      current = NodeCurrentStatus.find_or_initialize_by(node:)

      cases.each do |label, mutate|
        malformed = evidence
        mutate.call(malformed)
        supervisor.send(:update_status, current, payload('security_evidence' => malformed))

        expect(stored_report(current).dig('errors', 0, 'reason')).to include(label)
      end
      expect(node.node_kernel_events).to be_empty
    end

    it 'reloads evidence under the Node lock before deriving changes' do
      current = NodeCurrentStatus.find_or_initialize_by(node:)
      supervisor.send(
        :update_status,
        current,
        payload('security_evidence' => evidence)
      )
      first_worker = NodeCurrentStatus.find_by!(node:)
      second_worker = NodeCurrentStatus.find_by!(node:)
      VpsAdmin::API::KernelEvidence::SnapshotReader.call(first_worker.kernel_evidence)
      VpsAdmin::API::KernelEvidence::SnapshotReader.call(second_worker.kernel_evidence)

      with_module = evidence
      with_module['loaded_modules'] = ['kvm']
      supervisor.send(
        :update_status,
        first_worker,
        payload(
          'time' => (timestamp + 60).to_i,
          'security_evidence' => with_module
        )
      )
      supervisor.send(
        :update_status,
        second_worker,
        payload(
          'time' => (timestamp + 120).to_i,
          'security_evidence' => evidence
        )
      )

      expect(node.node_kernel_events.module_change.count).to eq(2)
      expect(stored_report(NodeCurrentStatus.find_by!(node:)).fetch('loaded_modules')).to be_empty
    end

    it 'does not let an out-of-order report regress current evidence' do
      current = NodeCurrentStatus.find_or_initialize_by(node:)
      supervisor.send(
        :update_status,
        current,
        payload(
          'time' => (timestamp + 120).to_i,
          'security_evidence' => evidence
        )
      )
      event_ids = node.node_kernel_events.ids
      delayed = evidence
      delayed['loaded_modules'] = ['kvm']

      supervisor.send(
        :update_status,
        NodeCurrentStatus.find_by!(node:),
        payload(
          'time' => (timestamp + 60).to_i,
          'security_evidence' => delayed
        )
      )

      current.reload
      expect(current.updated_at).to eq(timestamp + 120)
      expect(stored_report(current).fetch('loaded_modules')).to be_empty
      expect(node.node_kernel_events.ids).to eq(event_ids)
      expect(node.node_system_states.current.sole.last_observed_at).to eq(timestamp + 120)
    end

    it 'clears kernel data received from service-only nodes' do
      node.update!(role: :mailer)
      kernel_evidence = NodeKernelEvidence.new(node:, snapshot_type: :current)
      VpsAdmin::API::KernelEvidence::SnapshotWriter.call(
        snapshot: kernel_evidence,
        report: VpsAdmin::API::KernelEvidence::Report.from_hash(evidence),
        observed_at: timestamp,
        received_at: timestamp
      )
      current = NodeCurrentStatus.create!(
        node:,
        kernel: 'old-kernel',
        vpsadmin_version: 'spec',
        update_count: 1,
        created_at: timestamp - 60,
        updated_at: timestamp - 60,
        kernel_evidence:
      )

      supervisor.send(
        :update_status,
        current,
        payload('security_evidence' => { 'schema_version' => 1 })
      )

      current.reload
      expect(current.kernel).to be_nil
      expect(current.kernel_evidence).to be_nil
      expect(NodeKernelEvidence.where(id: kernel_evidence.id)).not_to exist
      expect(NodeStatus.find_by!(node:).kernel).to eq('')
      expect(node.node_kernel_events).to be_empty
      expect(node.node_system_states).to be_empty
    ensure
      node.update!(role: :node)
    end

    it 'stores a gap for malformed current evidence without losing node status' do
      current = NodeCurrentStatus.find_or_initialize_by(node:)

      expect do
        supervisor.send(
          :update_status,
          current,
          payload('security_evidence' => {
            'schema_version' => 1,
            'kernel' => { 'booted_at' => 'not-a-time' }
          })
        )
      end.not_to raise_error

      current.reload
      expect(current.kernel).to eq('6.8.0')
      expect(stored_report(current).dig('errors', 0, 'component')).to eq('security_evidence')
      expect(stored_report(current).dig('errors', 0, 'reason')).to start_with('invalid:')
      expect(node.node_kernel_events).to be_empty
    end
  end
end
