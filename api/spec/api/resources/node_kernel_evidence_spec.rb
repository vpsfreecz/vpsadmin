# frozen_string_literal: true

RSpec.describe VpsAdmin::API::Resources::NodeKernelEvidence do
  let(:node) { SpecSeed.node }
  let(:observed_at) { Time.current }
  let(:config_text) { "CONFIG_IPV6=y\n# CONFIG_KVM is not set\n" }
  let(:config_digest) { Digest::SHA256.hexdigest(config_text) }
  let(:vpsadminos_revision) { 'd' * 40 }

  before do
    header 'Accept', 'application/json'
    SpecSeed.admin
    SpecSeed.user
    node.update!(active: true, role: :node)
    node.node_statuses.delete_all
    node.node_kernel_events.delete_all
    node.node_kernel_evidences.destroy_all
    node.node_kernel_history_state&.destroy!
    NodeKernelConfiguration.delete_all
    VpsAdmin::API::KernelEvidence::ConfigurationWriter.call(
      digest: config_digest,
      content: config_text
    )
    current_evidence = store_evidence(:current)
    NodeCurrentStatus.find_or_create_by!(node:) do |status|
      status.vpsadmin_version = 'spec'
      status.kernel = '6.12.95'
      status.update_count = 1
    end.update!(kernel_evidence: current_evidence)
    NodeStatus.create!(
      node:,
      uptime: 3600,
      kernel: '6.12.95',
      vpsadmin_version: 'spec',
      created_at: observed_at - 1.hour
    )
    event = NodeKernelEvent.create!(
      node:,
      event_type: :boot,
      source: :node_report,
      confidence: :exact,
      boot_id: 'boot-a',
      booted_at: observed_at - 1.hour,
      booted_release: '6.12.95',
      reported_release: '6.12.95',
      observed_before: observed_at,
      current: true,
      kernel_evidence: store_evidence(:event)
    )
    event.software_changes.create!(
      generation: :booted,
      component: :vpsadminos,
      after_version: '2026.07',
      after_version_source: 'native',
      after_revision: vpsadminos_revision,
      after_revision_source: 'native'
    )
    event.sysctl_changes.create!(
      name: 'kernel.dmesg_restrict',
      after_available: true,
      after_configured_value: '1',
      after_effective_value: '1'
    )
  end

  def evidence
    {
      'schema_version' => 1,
      'kernel' => {
        'boot_id' => 'boot-a',
        'booted_at' => (observed_at - 1.hour).iso8601,
        'booted_release' => '6.12.95',
        'reported_release' => '6.12.95',
        'kernel_source_revision' => 'a2384967',
        'booted_params' => ['slab_nomerge', 'debug', 'debug=', 'debug=one=two', 'debug'],
        'command_line' => 'slab_nomerge debug debug= debug=one=two debug',
        'config_digest' => config_digest
      },
      'livepatches' => [{
        'id' => 'fix-cve',
        'kernel_version' => '6.12.95',
        'patch_version' => 2,
        'loaded' => true,
        'enabled' => true,
        'transition' => false,
        'patches' => [{ 'name' => 'fix_target', 'version' => 2 }]
      }],
      'ebpf_programs' => [{
        'name' => 'security-hook',
        'description' => 'security mitigation',
        'revision' => 'abc123',
        'digest' => 'digest',
        'active' => true,
        'bpfPrograms' => ['lsm_hook'],
        'links' => { 'lsm/file_open' => true }
      }],
      'deployment' => {
        'booted_system' => '/nix/store/booted-vpsadminos-system',
        'current_system' => '/nix/store/current-vpsadminos-system'
      },
      'loaded_modules' => %w[kvm kvm_amd],
      'software_versions' => %w[booted current].product(
        %w[vpsadminos vpsadmin nixpkgs]
      ).map do |generation, component|
        revision = if component == 'vpsadminos'
                     vpsadminos_revision
                   else
                     Digest::SHA1.hexdigest("#{generation}.#{component}")
                   end
        {
          'generation' => generation,
          'component' => component,
          'version' => component == 'vpsadminos' ? '2026.07' : "#{component}-version",
          'version_source' => 'native',
          'revision' => revision,
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
      'errors' => []
    }
  end

  def store_evidence(snapshot_type, report = evidence, time = observed_at, target: node)
    NodeKernelEvidence.new(node: target, snapshot_type:).tap do |record|
      VpsAdmin::API::KernelEvidence::SnapshotWriter.call(
        snapshot: record,
        report: VpsAdmin::API::KernelEvidence::Report.from_hash(report),
        observed_at: time,
        received_at: time
      )
    end
  end

  def replace_evidence(snapshot, report)
    VpsAdmin::API::KernelEvidence::SnapshotWriter.call(
      snapshot:,
      report: VpsAdmin::API::KernelEvidence::Report.from_hash(report),
      observed_at:,
      received_at: observed_at
    )
  end

  def json_get(path, params = nil)
    get path, params, {
      'CONTENT_TYPE' => 'application/json',
      'rack.input' => StringIO.new('{}')
    }
  end

  def index_path(resource)
    vpath("/#{resource}")
  end

  def rows(resource)
    json.dig('response', resource) || []
  end

  def admin_get(resource, filters = {})
    singular = resource.singularize
    as(SpecSeed.admin) do
      json_get index_path(resource), singular => filters
    end
  end

  it 'publishes only typed top-level evidence resources' do
    scopes = EndpointInventory.scopes_for_version(self, api_version)

    expect(scopes).to include(
      'node_kernel_evidence#index',
      'node_kernel_event#index',
      'node_kernel_configuration_option#index',
      'node_kernel_parameter#index',
      'node_kernel_module#index',
      'node_sysctl#index',
      'node_sysctl_change#index',
      'node_software_version#index',
      'node_software_deployment#index',
      'node_software_change#index',
      'node_kernel_livepatch#index',
      'node_kernel_livepatch_patch#index',
      'node_ebpf_program#index',
      'node_ebpf_program_object#index',
      'node_ebpf_program_link#index',
      'node_kernel_evidence_error#index',
      'node_kernel_history_state#index',
      'node_kernel_history_gap#index',
      'node_kernel_evidence#show',
      'node_kernel_event#show',
      'node_kernel_history_state#show',
      'node_kernel_livepatch#show',
      'node_ebpf_program#show'
    )
    expect(scopes).not_to include('node_kernel_evidence_gap#index')
    expect(scopes).not_to include('node.kernel_evidence#index')

    as(SpecSeed.admin) do
      options "#{index_path('node_kernel_evidences')}?method=GET"
    end
    parameters = json.dig('response', 'output', 'parameters')
    expect(parameters).to include(
      'node',
      'kernel_config_digest',
      'evidence_revision',
      'snapshot_revision'
    )
    expect(parameters).not_to include(
      'freshness',
      'history_complete',
      'history_started_at',
      'history_observed_through',
      'reconstruction_completed_at'
    )
    expect(parameters.values.map { |parameter| parameter['type'] }).not_to include('Custom')
    expect(parameters.fetch('node').fetch('type')).to eq('Resource')
    expect(parameters).not_to include('node_id', 'node_name', 'node_role', 'active')
  end

  it 'lists current evidence for all host nodes with a typed Node association' do
    admin_get('node_kernel_evidences', node_active: true)

    expect(last_response.status).to eq(200)
    row = rows('node_kernel_evidences').find { |item| item.dig('node', 'id') == node.id }
    expect(row).to include(
      'node' => include('id' => node.id),
      'boot_id' => 'boot-a',
      'kernel_config_digest' => config_digest,
      'kernel_config_available' => true,
      'booted_system' => '/nix/store/booted-vpsadminos-system'
    )
    expect(row['evidence_revision']).to match(/\A[0-9a-f]{64}\z/)
  end

  it 'shows every evidence resource used as an association target' do
    current = node.node_current_status.kernel_evidence
    event = node.node_kernel_events.reload.first
    history = NodeKernelHistoryState.create!(
      node:,
      completed_at: observed_at
    )
    targets = {
      'node_kernel_evidences' => current.id,
      'node_kernel_events' => event.id,
      'node_kernel_history_states' => history.id,
      'node_kernel_livepatches' => current.kernel_livepatches.sole.id,
      'node_ebpf_programs' => current.ebpf_programs.sole.id
    }

    targets.each do |resource, id|
      as(SpecSeed.admin) { json_get "#{index_path(resource)}/#{id}" }
      expect(last_response.status).to eq(200), "expected #{resource}##{id} to be shown"
    end
  end

  it 'lists exact private history with a baseline event for time filters' do
    newer = NodeKernelEvent.create!(
      node:,
      event_type: :livepatch_change,
      source: :node_report,
      confidence: :exact,
      boot_id: 'boot-a',
      booted_at: observed_at - 1.hour,
      booted_release: '6.12.95',
      reported_release: '6.12.95',
      observed_before: observed_at + 1.minute,
      current: true,
      kernel_evidence: store_evidence(:event, evidence, observed_at + 1.minute)
    )

    admin_get(
      'node_kernel_events',
      node: node.id,
      from: (observed_at + 30.seconds).iso8601
    )

    returned = rows('node_kernel_events')
    expect(returned.map { |event| event['id'] }).to eq(
      [node.node_kernel_events.minimum(:id), newer.id]
    )
    expect(returned.first).to include(
      'source' => 'node_report',
      'confidence' => 'exact',
      'kernel_source_revision' => 'a2384967'
    )
  end

  it 'selects a filtered pre-window baseline independently for every Node' do
    other_node = SpecSeed.other_node
    other_node.node_kernel_events.delete_all
    primary_boot = node.node_kernel_events.boot.sole
    other_boot = NodeKernelEvent.create!(
      node: other_node,
      event_type: :boot,
      source: :node_report,
      confidence: :exact,
      boot_id: 'other-boot',
      booted_at: observed_at - 1.hour,
      booted_release: '6.12.95',
      reported_release: '6.12.95',
      observed_before: observed_at + 5.seconds,
      current: true,
      kernel_evidence: store_evidence(
        :event,
        evidence,
        observed_at + 5.seconds,
        target: other_node
      )
    )
    [node, other_node].each_with_index do |target, index|
      NodeKernelEvent.create!(
        node: target,
        event_type: :livepatch_change,
        source: :node_report,
        confidence: :exact,
        boot_id: "later-#{index}",
        booted_release: '6.12.95',
        reported_release: '6.12.95',
        observed_before: observed_at + 10.seconds + index.seconds,
        current: true,
        kernel_evidence: store_evidence(
          :event,
          evidence,
          observed_at + 10.seconds + index.seconds,
          target:
        )
      )
    end

    admin_get(
      'node_kernel_events',
      from: (observed_at + 30.seconds).iso8601,
      event_type: 'boot'
    )

    expect(rows('node_kernel_events').pluck('id')).to contain_exactly(
      primary_boot.id,
      other_boot.id
    )
  end

  it 'paginates large event histories in the database without omissions' do
    event_evidence = NodeKernelEvent.where(node:).first.kernel_evidence
    values = 1001.times.map do |index|
      event_time = observed_at + index.seconds + 1.minute
      {
        node_id: node.id,
        node_kernel_evidence_id: event_evidence.id,
        event_type: NodeKernelEvent.event_types.fetch('module_change'),
        source: NodeKernelEvent.sources.fetch('node_report'),
        confidence: NodeKernelEvent.confidences.fetch('exact'),
        boot_id: 'boot-a',
        booted_release: '6.12.95',
        reported_release: '6.12.95',
        observed_before: event_time,
        current: true,
        created_at: event_time,
        updated_at: event_time
      }
    end
    NodeKernelEvent.insert_all!(values)

    expected_ids = NodeKernelEvent.where(node:).order(:id).ids
    admin_get('node_kernel_events', node: node.id, limit: 1000)
    first_page = rows('node_kernel_events').pluck('id')
    admin_get(
      'node_kernel_events',
      node: node.id,
      from_id: first_page.last,
      limit: 1000
    )
    second_page = rows('node_kernel_events').pluck('id')

    expect(first_page.length).to eq(1000)
    expect(first_page + second_page).to eq(expected_ids)
  end

  it 'filters relational kernel options by node and exact option name' do
    admin_get(
      'node_kernel_configuration_options',
      node: node.id,
      node_active: true,
      name: 'CONFIG_KVM'
    )

    expect(rows('node_kernel_configuration_options')).to contain_exactly(
      include(
        'configuration_digest' => config_digest,
        'name' => 'CONFIG_KVM',
        'value' => 'n'
      )
    )
  end

  it 'returns independently filterable runtime component rows' do
    admin_get(
      'node_kernel_parameters',
      node: node.id,
      source: 'current',
      name: 'debug'
    )
    expect(
      rows('node_kernel_parameters').map do |row|
        row.slice('position', 'name', 'value')
      end
    ).to eq(
      [
        { 'position' => 1, 'name' => 'debug', 'value' => nil },
        { 'position' => 2, 'name' => 'debug', 'value' => '' },
        { 'position' => 3, 'name' => 'debug', 'value' => 'one=two' },
        { 'position' => 4, 'name' => 'debug', 'value' => nil }
      ]
    )

    admin_get(
      'node_kernel_modules',
      node: node.id,
      node_active: true,
      source: 'current',
      name: 'kvm'
    )
    expect(rows('node_kernel_modules')).to contain_exactly(
      include('node' => include('id' => node.id), 'source' => 'current', 'name' => 'kvm')
    )

    admin_get('node_sysctls', node: node.id)
    expect(rows('node_sysctls')).to contain_exactly(
      include(
        'name' => 'kernel.dmesg_restrict',
        'available' => true,
        'configured_value' => '1',
        'effective_value' => '1'
      ),
      include(
        'name' => 'kernel.dmesg_restrict',
        'available' => true,
        'configured_value' => '1',
        'effective_value' => '1'
      )
    )

    livepatch = node.node_current_status.kernel_evidence.kernel_livepatches.sole
    admin_get('node_kernel_livepatch_patches', node: node.id, source: 'current')
    expect(rows('node_kernel_livepatch_patches')).to contain_exactly(
      include(
        'node_kernel_livepatch' => include('id' => livepatch.id),
        'name' => 'fix_target',
        'version' => '2'
      )
    )

    program = node.node_current_status.kernel_evidence.ebpf_programs.sole
    admin_get('node_ebpf_program_links', node: node.id, source: 'current')
    expect(rows('node_ebpf_program_links')).to contain_exactly(
      include(
        'node_ebpf_program' => include('id' => program.id),
        'name' => 'lsm/file_open',
        'attached' => true
      )
    )

    admin_get('node_ebpf_programs', node: node.id, source: 'current', active: true)
    programs = rows('node_ebpf_programs')
    expect(programs.length).to eq(1)
    expect(programs.first).to include('name' => 'security-hook', 'active' => true)
  end

  it 'returns software identities, grouped deployments and per-name sysctl history' do
    admin_get(
      'node_software_versions',
      node: node.id,
      source: 'current',
      version_source: 'native',
      revision_source: 'native',
      revision_dirty: false
    )
    expect(rows('node_software_versions')).to include(
      include(
        'generation' => 'booted',
        'component' => 'vpsadminos',
        'version' => '2026.07',
        'version_source' => 'native',
        'revision' => vpsadminos_revision,
        'revision_source' => 'native',
        'revision_dirty' => false
      )
    )

    node.node_current_status.kernel_evidence.software_versions.create!(
      generation: :current,
      component: :vpsfree_cz_configuration,
      revision: 'd' * 40,
      revision_source: :native,
      revision_dirty: true
    )
    admin_get(
      'node_software_versions',
      node: node.id,
      component: 'vpsfree_cz_configuration',
      revision_dirty: true
    )
    expect(rows('node_software_versions')).to contain_exactly(
      include(
        'generation' => 'current',
        'component' => 'vpsfree_cz_configuration',
        'version' => nil,
        'revision' => 'd' * 40,
        'revision_source' => 'native',
        'revision_dirty' => true
      )
    )

    admin_get('node_software_deployments', node: node.id)
    expect(rows('node_software_deployments')).to contain_exactly(
      include('event_type' => 'boot', 'change_count' => 1)
    )

    event_id = node.node_kernel_events.boot.sole.id
    admin_get('node_software_changes', node: node.id, node_kernel_event: event_id)
    expect(rows('node_software_changes')).to contain_exactly(
      include(
        'generation' => 'booted',
        'component' => 'vpsadminos',
        'after_revision' => vpsadminos_revision,
        'after_revision_source' => 'native',
        'after_revision_dirty' => false
      )
    )

    admin_get('node_sysctl_changes', node: node.id, name: 'kernel.dmesg_restrict')
    expect(rows('node_sysctl_changes')).to contain_exactly(
      include(
        'name' => 'kernel.dmesg_restrict',
        'after_available' => true,
        'after_effective_value' => '1'
      )
    )
  end

  it 'returns reported collection errors and stored reconstruction coverage facts' do
    report = evidence.deep_dup
    report['errors'] = [{
      'component' => 'kernel_config',
      'reason' => 'configuration content could not be read'
    }]
    replace_evidence(node.node_current_status.kernel_evidence, report)
    history = NodeKernelHistoryState.create!(
      node:,
      from_status_id: 10,
      through_status_id: 20,
      started_at: observed_at - 2.hours,
      observed_through: observed_at,
      completed_at: observed_at + 1.minute
    )
    gap = history.kernel_history_gaps.create!(
      from: observed_at - 90.minutes,
      to: observed_at - 60.minutes,
      reason: 'status interval is missing'
    )

    admin_get(
      'node_kernel_evidence_errors',
      node: node.id,
      source: 'current',
      component: 'kernel_config'
    )
    expect(rows('node_kernel_evidence_errors')).to contain_exactly(
      include(
        'node' => include('id' => node.id),
        'source' => 'current',
        'component' => 'kernel_config',
        'reason' => 'configuration content could not be read'
      )
    )

    admin_get('node_kernel_history_states', node: node.id)
    history_rows = rows('node_kernel_history_states')
    expect(history_rows).to contain_exactly(
      include(
        'id' => history.id,
        'from_status_id' => 10,
        'through_status_id' => 20
      )
    )
    expect(Time.iso8601(history_rows.first.fetch('observed_through')))
      .to be_within(1.second).of(history.reload.observed_through)

    admin_get(
      'node_kernel_history_gaps',
      node: node.id,
      from: (observed_at - 75.minutes).iso8601,
      to: (observed_at - 70.minutes).iso8601
    )
    expect(rows('node_kernel_history_gaps')).to contain_exactly(
      include(
        'id' => gap.id,
        'node_kernel_history_state' => include('id' => history.id),
        'reason' => 'status interval is missing'
      )
    )
  end

  it 'does not change the evidence revision for unrelated status samples' do
    admin_get('node_kernel_evidences', node: node.id)
    before = rows('node_kernel_evidences').first.fetch('evidence_revision')

    NodeStatus.create!(
      node:,
      uptime: 4500,
      kernel: '6.12.95',
      vpsadmin_version: 'spec',
      created_at: observed_at + 15.minutes
    )

    admin_get('node_kernel_evidences', node: node.id)
    expect(rows('node_kernel_evidences').first.fetch('evidence_revision')).to eq(before)
  end

  it 'excludes service-only nodes from all evidence resources' do
    node.update!(role: :mailer)

    %w[
      node_kernel_evidences
      node_kernel_events
      node_kernel_configuration_options
      node_kernel_parameters
      node_kernel_modules
      node_sysctls
      node_sysctl_changes
      node_software_versions
      node_software_deployments
      node_software_changes
      node_kernel_livepatches
      node_kernel_livepatch_patches
      node_ebpf_programs
      node_ebpf_program_objects
      node_ebpf_program_links
      node_kernel_evidence_errors
      node_kernel_history_states
      node_kernel_history_gaps
    ].each do |resource|
      admin_get(resource, node: node.id)
      expect(rows(resource)).to be_empty, "expected #{resource} to exclude service Nodes"
    end
  ensure
    node.update!(role: :node)
  end

  it 'resolves typed associations with only the required read scopes' do
    history = NodeKernelHistoryState.create!(node:, completed_at: observed_at)
    history.kernel_history_gaps.create!(
      from: observed_at - 2.hours,
      to: observed_at - 1.hour,
      reason: 'spec gap'
    )
    session = create_open_session!(
      user: SpecSeed.admin,
      auth_type: 'token',
      token_lifetime: 'permanent',
      scope: %w[
        node#show
        node_kernel_evidence#show
        node_kernel_event#index
        node_kernel_module#index
        node_kernel_livepatch#show
        node_kernel_livepatch_patch#index
        node_ebpf_program#show
        node_ebpf_program_object#index
        node_kernel_history_state#show
        node_kernel_history_gap#index
      ]
    )
    header 'X-HaveAPI-Auth-Token', session.token.token

    %w[
      node_kernel_events
      node_kernel_modules
      node_kernel_livepatch_patches
      node_ebpf_program_objects
      node_kernel_history_gaps
    ].each do |resource|
      scope = resource.singularize
      json_get index_path(resource), scope => { node: node.id }
      expect(last_response.status).to eq(200), "expected #{resource} to be readable"
      expect(rows(resource)).not_to be_empty
    end
    expect(rows('node_kernel_modules')).to all(
      include(
        'node' => include('id' => node.id),
        'node_kernel_evidence' => include('id' => a_kind_of(Integer))
      )
    )
  ensure
    header 'X-HaveAPI-Auth-Token', nil
  end

  it 'forbids normal users' do
    as(SpecSeed.user) { json_get index_path('node_kernel_evidences') }

    expect(last_response.status).to eq(403)
  end
end
