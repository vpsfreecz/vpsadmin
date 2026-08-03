# frozen_string_literal: true

require 'spec_helper'

RSpec.describe VpsAdmin::API::Events::ResourceOperations do
  before do
    create_spec_event_route!(user: SpecSeed.user)
    create_spec_event_route!(user: SpecSeed.admin)
    create_spec_event_route!(
      user: SpecSeed.admin,
      subject_scope: :visible
    )
  end

  def policy_constant(name, plugin: nil)
    klass = name.safe_constantize
    return klass if klass
    return if plugin && !SpecPlugins.enabled?(plugin)

    raise NameError, "event policy constant #{name} is not loaded"
  end

  it 'does not persist a typed resource fact without a delivery route' do
    EventRoute.where(user: [SpecSeed.user, SpecSeed.admin]).delete_all
    event = nil

    expect do
      event = with_current_context(user: SpecSeed.user) do
        described_class.updated!(
          SpecSeed.user,
          changed_fields: [:login]
        )
      end
    end.not_to(change { event_storage_counts })

    expect(event).to be_nil
  end

  it 'records typed changes and redacts sensitive values' do
    event = with_current_context(user: SpecSeed.user) do |session|
      described_class.updated!(
        SpecSeed.user,
        changed_fields: %i[password login password]
      ).tap do |created_event|
        expect(created_event.user).to eq(SpecSeed.user)
        expect(created_event.ip_addr).to eq(session.client_ip_addr || session.api_ip_addr)
      end
    end

    expect(event).to be_persisted
    expect(event.event_type).to eq('user.updated')
    expect(event.source_class).to eq('User')
    expect(event.source_id).to eq(SpecSeed.user.id)
    expect(event.parameters).to include(
      'resource_name' => 'user',
      'resource_id' => SpecSeed.user.id,
      'resource_action' => 'updated',
      'resource_schema_version' => 1,
      'actor_user_id' => SpecSeed.user.id,
      'actor_user_login' => SpecSeed.user.login,
      'changed_fields' => %w[login password]
    )
    expect(event.parameters.dig('changes', 'password', 'new'))
      .to eq('kind' => 'redacted')
    expect(event.payload_json).not_to include(SpecSeed::PASSWORD)
  end

  it 'preserves explicit nulls and digests oversized values' do
    payload = described_class.payload_for(
      :updated,
      SpecSeed.os_family,
      changes: {
        description: {
          old: nil,
          new: 'x' * (described_class::MAX_INLINE_VALUE_BYTES + 1)
        }
      },
      actor: nil,
      session: nil
    )

    expect(payload.dig(:changes, 'description', 'old')).to eq(
      'kind' => 'value',
      'value' => nil
    )
    expect(payload.dig(:changes, 'description', 'new')).to include(
      'kind' => 'digest',
      'algorithm' => 'sha256',
      'bytes' => described_class::MAX_INLINE_VALUE_BYTES + 3
    )
    expect(payload.dig(:changes, 'description', 'new', 'digest'))
      .to match(/\A[0-9a-f]{64}\z/)
  end

  it 'redacts model-specific configuration, content, and user-data values' do
    sysconfig = SysConfig.new(id: 42, category: 'test', name: 'secret', value: 'do not expose')
    user_data = VpsUserData.new(id: 43, content: 'private bootstrap script')
    os_template = OsTemplate.new(id: 44, config: { 'provider_token' => 'do not expose' })
    template_variant = NotificationTemplateVariant.new(
      id: 45,
      text: 'private plaintext template',
      html: '<p>private HTML template</p>'
    )

    sysconfig_payload = described_class.payload_for(
      :updated,
      sysconfig,
      changes: { value: { old: 'before', new: 'after' } },
      actor: nil,
      session: nil
    )
    user_data_payload = described_class.payload_for(
      :updated,
      user_data,
      changes: { content: { old: 'before', new: 'after' } },
      actor: nil,
      session: nil
    )
    os_template_payloads = %i[created updated deleted].to_h do |action|
      [
        action,
        described_class.payload_for(
          action,
          os_template,
          changes: {
            config: {
              old: { 'provider_token' => 'before' },
              new: { 'provider_token' => 'after' }
            }
          },
          actor: nil,
          session: nil
        )
      ]
    end
    template_variant_payloads = %i[created updated deleted].to_h do |action|
      [
        action,
        described_class.payload_for(
          action,
          template_variant,
          changes: {
            text: { old: 'old text', new: 'new text' },
            html: { old: 'old html', new: 'new html' }
          },
          actor: nil,
          session: nil
        )
      ]
    end

    expect(sysconfig_payload.dig(:changes, 'value')).to eq(
      'old' => { 'kind' => 'redacted' },
      'new' => { 'kind' => 'redacted' }
    )
    expect(user_data_payload.dig(:changes, 'content')).to eq(
      'old' => { 'kind' => 'redacted' },
      'new' => { 'kind' => 'redacted' }
    )
    expect(os_template_payloads[:created].dig(:changes, 'config')).to eq(
      'new' => { 'kind' => 'redacted' }
    )
    expect(os_template_payloads[:updated].dig(:changes, 'config')).to eq(
      'old' => { 'kind' => 'redacted' },
      'new' => { 'kind' => 'redacted' }
    )
    expect(os_template_payloads[:deleted].dig(:changes, 'config')).to eq(
      'old' => { 'kind' => 'redacted' }
    )
    expect(template_variant_payloads[:created].dig(:changes, 'text')).to eq(
      'new' => { 'kind' => 'redacted' }
    )
    expect(template_variant_payloads[:updated].dig(:changes, 'html')).to eq(
      'old' => { 'kind' => 'redacted' },
      'new' => { 'kind' => 'redacted' }
    )
    expect(template_variant_payloads[:deleted].dig(:changes, 'text')).to eq(
      'old' => { 'kind' => 'redacted' }
    )

    %i[created updated deleted].each do |action|
      descriptor = described_class.resource_descriptor(OsTemplate, action)
      config = descriptor.fetch(:attributes).detect { |attribute| attribute.fetch(:name) == 'config' }
      expect(config).to include(
        type: 'json',
        value_policy: 'redacted',
        old_matcher: false,
        new_matcher: false
      )
    end

    %i[created updated deleted].each do |action|
      descriptor = described_class.resource_descriptor(
        NotificationTemplateVariant,
        action
      )
      %w[html text].each do |name|
        attribute = descriptor.fetch(:attributes).detect do |candidate|
          candidate.fetch(:name) == name
        end
        expect(attribute).to include(
          type: 'string',
          value_policy: 'redacted',
          old_matcher: false,
          new_matcher: false
        )
      end
    end
  end

  it 'exposes only inline old and new values to route matchers' do
    event = described_class.updated!(
      SpecSeed.os_family,
      changed_fields: %i[label description],
      changes: {
        label: { old: 'Before', new: 'After' },
        description: {
          old: 'small',
          new: 'x' * (described_class::MAX_INLINE_VALUE_BYTES + 1)
        }
      }
    )

    expect(EventRouteMatcher.field_value(event, 'old_label')).to eq('Before')
    expect(EventRouteMatcher.field_value(event, 'new_label')).to eq('After')
    expect(EventRouteMatcher.field_value(event, 'new_description')).to be_nil
  end

  it 'predicts sequential transaction confirmation counter changes' do
    policies = VpsAdmin::API::Events::ActionPolicies
    recorder = policies::Recorder.new(
      policies::Policy.new(
        kind: :transaction_chain,
        models: %w[SnapshotInPool],
        reason: 'sequential counter confirmation spec',
        atomic: false
      )
    )
    snapshot = SnapshotInPool.new(reference_count: 10)
    increment = TransactionConfirmation.new(
      confirm_type: :increment_type,
      attr_changes: 'reference_count'
    )
    first_changes = recorder.send(
      :confirmation_changes,
      increment,
      snapshot,
      previous: nil
    )
    first = policies::Recorder::Fact.new(
      action: :updated,
      object: snapshot,
      owner: nil,
      vps: nil,
      changed_fields: %w[reference_count],
      changes: first_changes
    )
    second_changes = recorder.send(
      :confirmation_changes,
      increment,
      snapshot,
      previous: first
    )
    second = policies::Recorder::Fact.new(
      action: :updated,
      object: snapshot,
      owner: nil,
      vps: nil,
      changed_fields: %w[reference_count],
      changes: second_changes
    )
    decrement = TransactionConfirmation.new(
      confirm_type: :decrement_type,
      attr_changes: { 'reference_count' => 3 }
    )

    expect(first_changes.fetch('reference_count')).to eq(old: 10, new: 11)
    expect(second_changes.fetch('reference_count')).to eq(old: 11, new: 12)
    expect(
      recorder.send(
        :confirmation_changes,
        decrement,
        snapshot,
        previous: second
      ).fetch('reference_count')
    ).to eq(old: 12, new: 9)
  end

  it 'records an administrator mutation of a system resource as a system event' do
    event = with_current_context(user: SpecSeed.admin) do
      described_class.created!(SpecSeed.node)
    end

    expect(event).to be_persisted
    expect(event.user).to be_nil
    expect(event.source_class).to eq('Node')
    expect(event.source_id).to eq(SpecSeed.node.id)
    expect(event.parameters).to include(
      'resource_name' => 'node',
      'resource_id' => SpecSeed.node.id,
      'resource_action' => 'created',
      'actor_user_id' => SpecSeed.admin.id
    )
  end

  it 'does not make a support actor the owner of a system resource event' do
    event = with_current_context(user: SpecSeed.support) do
      described_class.updated!(SpecSeed.node, changed_fields: %i[active])
    end

    expect(event).to be_persisted
    expect(event.user).to be_nil
    expect(event.parameters).to include(
      'actor_user_id' => SpecSeed.support.id,
      'changed_fields' => %w[active]
    )
  end

  it 'publishes typed resource events and their attribute contracts' do
    described_class.refresh_event_types!

    type = VpsAdmin::API::Events.type_for('vps.updated')
    expect(type).to be_present
    expect(type.resource).to include(
      name: 'vps',
      action: 'updated',
      schema_version: 1,
      id_type: 'integer'
    )
    expect(type.resource.fetch(:attributes).map { |field| field.fetch(:name) })
      .to include('hostname', 'object_state')
    expect(VpsAdmin::API::Events.type_for('resource.updated')).to be_nil
    object_state = type.resource.fetch(:attributes).detect do |field|
      field.fetch(:name) == 'object_state'
    end
    expect(object_state).to include(
      type: 'string',
      choices: VpsAdmin::API::Lifetimes::STATES.map(&:to_s),
      old_matcher: true,
      new_matcher: true
    )

    route = EventRoute.new(
      user: SpecSeed.user,
      label: 'Typed resource matcher',
      event_type: 'vps.updated'
    )
    matcher = EventRouteMatcher.new(
      event_route: route,
      field: 'new_hostname',
      operator: '==',
      value: 'vps.example.test'
    )
    expect(matcher).to be_valid

    state_event = Event.new(
      event_type: 'vps.updated',
      payload: described_class.payload_for(
        :updated,
        Vps.new(id: 42),
        changes: {
          object_state: {
            old: 'active',
            new: 'suspended'
          }
        },
        actor: nil,
        session: nil
      )
    )
    state_matcher = EventRouteMatcher.new(
      event_route: route,
      field: 'new_object_state',
      operator: '==',
      value: 'suspended'
    )
    expect(state_matcher).to be_valid
    expect(state_matcher.field_type).to eq('string')
    expect(state_matcher.matches?(state_event)).to be(true)

    descriptor = described_class.resource_descriptor(EventTimeInterval, :updated)
    serialized = descriptor.fetch(:attributes).detect do |field|
      field.fetch(:name) == 'specs'
    end
    expect(serialized).to include(
      type: 'json',
      value_policy: 'value_or_digest',
      old_matcher: false,
      new_matcher: false
    )
  end

  it 'publishes only catalogued public resource actions and topics' do
    described_class.refresh_event_types!

    expect(VpsAdmin::API::Events.type_for('vps.updated')).to have_attributes(
      category: 'vps',
      audience: :account,
      roles: contain_exactly('account', 'admin')
    )
    expect(
      VpsAdmin::API::Events.type_for('os_family.updated')
    ).to have_attributes(
      category: 'operating_systems',
      audience: :admin,
      roles: contain_exactly('admin')
    )
    expect(VpsAdmin::API::Events.type_for('cluster_resource.deleted')).to be_nil
    expect(VpsAdmin::API::Events.type_for('vps_feature.created')).to be_nil

    %w[
      auth_token
      network_interface_daily_accounting
      network_interface_monthly_accounting
      network_interface_yearly_accounting
      snapshot_in_pool
      snapshot_in_pool_clone
      snapshot_in_pool_in_branch
      token
      webauthn_challenge
    ].each do |resource_name|
      described_class::ACTIONS.each do |action|
        expect(
          VpsAdmin::API::Events.type_for("#{resource_name}.#{action}")
        ).to be_nil
      end
    end

    categories = VpsAdmin::API::Events.types.map(&:category).uniq
    expect(categories - described_class::TOPICS).to be_empty

    expect do
      described_class.ensure_event_type!(SnapshotInPool, :updated)
    end.to raise_error(
      ArgumentError,
      /not an outside-visible resource event model/
    )
  end

  it 'silently ignores internal models captured by broad mutation policies' do
    policies = VpsAdmin::API::Events::ActionPolicies
    recorder = policies::Recorder.new(
      policies::Policy.new(
        kind: :transaction_chain,
        models: :all,
        reason: 'internal model filtering spec',
        atomic: false
      )
    )

    recorder.record(
      :created,
      SnapshotInPool.new(id: 123, reference_count: 1)
    )
    recorder.record(:created, Token.new(id: 456))

    expect(recorder).not_to be_pending
  end

  it 'keeps semantic update notifications separate from resource facts' do
    described_class.refresh_event_types!

    reserved_types = VpsAdmin::API::Events.types.select do |type|
      type.name.match?(/\.(created|updated|deleted)\z/)
    end
    malformed_types = reserved_types.reject do |type|
      resource_name, action = type.name.split('.', 2)

      type.resource_generated &&
        type.resource&.values_at(:name, :action) == [resource_name, action]
    end
    expect(malformed_types).to be_empty,
                               'Reserved mutation event types must be generated ' \
                               "resource facts: #{malformed_types.map(&:name).sort.join(', ')}"

    expect(VpsAdmin::API::Events.type_for('user.created').resource).to include(
      name: 'user',
      action: 'created'
    )
    if SpecPlugins.enabled?(:outage_reports)
      expect(VpsAdmin::API::Events.type_for('outage.updated').resource).to include(
        name: 'outage',
        action: 'updated'
      )
      expect(
        VpsAdmin::API::Events.type_for('outage.update_reported').resource
      ).to be_nil
    end

    expect(
      VpsAdmin::API::Events.type_for('security_advisory.updated').resource
    ).to include(
      name: 'security_advisory',
      action: 'updated'
    )
    expect(
      VpsAdmin::API::Events.type_for(
        'security_advisory.update_published'
      ).resource
    ).to be_nil
    expect(
      VpsAdmin::API::Events.type_for('user.account_created').resource
    ).to be_nil

    if SpecPlugins.enabled?(:requests)
      expect(
        VpsAdmin::API::Events.type_for('request.created').resource
      ).to include(name: 'request', action: 'created')
      expect(
        VpsAdmin::API::Events.type_for('request.updated').resource
      ).to include(name: 'request', action: 'updated')
      expect(
        VpsAdmin::API::Events.type_for('request.submitted').resource
      ).to be_nil
      expect(
        VpsAdmin::API::Events.type_for('request.update_submitted').resource
      ).to be_nil
    end

    malformed = Event.new(
      event_type: 'outage.updated',
      payload: { 'changes' => [] }
    )
    expect(EventRouteMatcher.field_value(malformed, 'new_state')).to be_nil
  end

  it 'describes encoded values without publishing network accounting events' do
    decimal = ClusterResource.new(id: 42)
    decimal_payload = described_class.payload_for(
      :updated,
      decimal,
      changes: {
        max: {
          old: BigDecimal('1.25'),
          new: BigDecimal('2.50')
        }
      },
      actor: nil,
      session: nil
    )
    decimal_descriptor = described_class.resource_descriptor(
      ClusterResource,
      :updated
    )
    max_attribute = decimal_descriptor.fetch(:attributes).detect do |attribute|
      attribute.fetch(:name) == 'max'
    end

    expect(max_attribute.fetch(:type)).to eq('string')
    expect(decimal_payload.dig(:changes, 'max')).to eq(
      'old' => { 'kind' => 'value', 'value' => '1.25' },
      'new' => { 'kind' => 'value', 'value' => '2.5' }
    )

    accounting = NetworkInterfaceMonthlyAccounting.new(
      network_interface_id: 11,
      user_id: 22,
      year: 2026,
      month: 7
    )
    composite_payload = described_class.payload_for(
      :updated,
      accounting,
      changes: { bytes_in: { old: 10, new: 20 } },
      actor: nil,
      session: nil
    )
    composite_descriptor = described_class.resource_descriptor(
      NetworkInterfaceMonthlyAccounting,
      :updated
    )

    expect(composite_payload.fetch(:resource_id)).to eq(
      'network_interface_id' => 11,
      'user_id' => 22,
      'year' => 2026,
      'month' => 7
    )
    expect(composite_descriptor).to include(
      id_type: 'object',
      id_attributes: [
        { name: 'network_interface_id', type: 'integer' },
        { name: 'user_id', type: 'integer' },
        { name: 'year', type: 'integer' },
        { name: 'month', type: 'integer' }
      ]
    )

    expect(described_class.catalogued?(NetworkInterfaceMonthlyAccounting))
      .to be(false)
    expect do
      described_class.ensure_event_type!(
        NetworkInterfaceMonthlyAccounting,
        :updated
      )
    end.to raise_error(
      ArgumentError,
      /not an outside-visible resource event model/
    )

    now = Time.now
    accounting_id = [
      9_000_000 + Process.pid,
      SpecSeed.user.id,
      2026,
      7
    ]
    NetworkInterfaceMonthlyAccounting.insert!({
      network_interface_id: accounting_id[0],
      user_id: accounting_id[1],
      year: accounting_id[2],
      month: accounting_id[3],
      bytes_in: 10,
      bytes_out: 20,
      packets_in: 1,
      packets_out: 2,
      created_at: now,
      updated_at: now
    })
    persisted_accounting = NetworkInterfaceMonthlyAccounting.find(accounting_id)
    policy = VpsAdmin::API::Events::ActionPolicies::Policy.new(
      kind: :resource,
      models: %w[NetworkInterfaceMonthlyAccounting],
      reason: nil,
      atomic: true
    )
    VpsAdmin::API::Events::ActionPolicies.capture(policy) do
      persisted_accounting.update!(bytes_in: 20)
    end

    expect(
      Event.where(
        event_type: 'network_interface_monthly_accounting.updated',
        source_class: 'NetworkInterfaceMonthlyAccounting'
      ).count
    ).to eq(0)
  end

  it 'classifies every mutating API action' do
    ApiAppHelper.app_instance

    expect do
      VpsAdmin::API::Events::ActionPolicies.finalize!
    end.not_to raise_error
  end

  it 'rejects an unclassified mutating action in a nested mounted resource' do
    action = Class.new(HaveAPI::Action) do
      http_method :post
    end
    allow(action).to receive(:name).and_return('SpecResources::Nested::Mutate')

    nested_resource = Class.new(HaveAPI::Resource)
    allow(nested_resource).to receive(:actions).and_yield(action)
    allow(nested_resource).to receive(:resources)

    root_resource = Class.new(HaveAPI::Resource)
    allow(root_resource).to receive(:actions)
    allow(root_resource).to receive(:resources).and_yield(nested_resource)
    allow(HaveAPI).to receive(:get_version_resources).and_return([root_resource])

    expect do
      VpsAdmin::API::Events::ActionPolicies.finalize!
    end.to raise_error(
      ArgumentError,
      /mounted mutating actions.*SpecResources::Nested::Mutate/m
    )
    expect(HaveAPI).to have_received(:get_version_resources).with(
      VpsAdmin::API::Resources,
      HaveAPI.implicit_version
    )
  end

  it 'catalogues every mounted model-backed CRUD resource' do
    ApiAppHelper.app_instance

    walk_resource = lambda do |resource|
      resources = [resource]
      resource.resources { |child| resources.concat(walk_resource.call(child)) }
      resources
    end
    resources =
      HaveAPI.get_version_resources(VpsAdmin::API::Resources, '7.0').flat_map do |resource|
        walk_resource.call(resource)
      end

    missing = resources.filter_map do |resource|
      next unless resource.model

      actions = resource.actions.filter_map do |action|
        if action <= HaveAPI::Actions::Default::Create
          'created'
        elsif action <= HaveAPI::Actions::Default::Update
          'updated'
        elsif action <= HaveAPI::Actions::Default::Delete
          'deleted'
        end
      end.uniq
      next if actions.empty?

      entry = described_class.catalog_entry_for(resource.model)
      missing_actions = entry ? actions - entry.actions : actions
      next if missing_actions.empty?

      "#{resource.name}: #{missing_actions.sort.join(', ')}"
    end

    expect(missing).to be_empty,
                       "Uncatalogued public CRUD actions:\n#{missing.sort.join("\n")}"
  end

  it 'derives the catalog from owning resource classes' do
    catalog = described_class.resource_catalog

    expect(catalog.fetch('User').api_resources).to contain_exactly(
      VpsAdmin::API::Resources::User
    )
    expect(catalog.fetch('MigrationPlan').actions)
      .to contain_exactly('created', 'updated', 'deleted')
    expect(catalog.fetch('UserDevice').actions)
      .to contain_exactly('created', 'deleted')
    expect(catalog.fetch('SysConfig').actions).to contain_exactly('updated')
  end

  it 'resolves operation owners from resource and internal model declarations' do
    dataset = instance_double(Dataset, user: SpecSeed.user)
    dataset_in_pool = instance_double(DatasetInPool, dataset:)
    dataset_tree = instance_double(DatasetTree, dataset_in_pool:)
    branch = instance_double(Branch, dataset_tree:)

    expect(DatasetInPool.operation_event_owner_for(dataset_in_pool))
      .to eq(SpecSeed.user)
    expect(Branch.operation_event_owner_for(branch)).to eq(SpecSeed.user)

    host_address = instance_double(HostIpAddress, current_owner: SpecSeed.user)
    expect(HostIpAddress.operation_event_owner_for(host_address))
      .to eq(SpecSeed.user)
    expect(described_class.catalog_entry_for(HostIpAddress).owner).to be_nil

    if SpecPlugins.enabled?(:outage_reports)
      handler = instance_double(OutageHandler, user: SpecSeed.user)
      expect(described_class.catalog_entry_for(OutageHandler).owner.call(handler))
        .to eq(SpecSeed.user)
    end
  end

  it 'rejects duplicate resource and action policy declarations' do
    expect do
      VpsAdmin::API::Resources::User.resource_events(
        topic: :account,
        audience: :account,
        owner: :self
      )
    end.to raise_error(ArgumentError, /already declared/)

    expect do
      VpsAdmin::API::Resources::User::Update.event_policy(
        :resource,
        models: [::User]
      )
    end.to raise_error(ArgumentError, /already declared/)

    expect { Event.event_redact(:parameters) }
      .to raise_error(ArgumentError, /already declared/)
    expect { User.event_delete_cascades(:user_notification_rate_limits) }
      .to raise_error(ArgumentError, /already declared/)
  end

  it 'rejects unsupported action policy kinds and ignored policy options' do
    action = Class.new(HaveAPI::Action)
    operation = Class.new(VpsAdmin::API::Operations::Base)
    policies = VpsAdmin::API::Events::ActionPolicies

    expect do
      action.event_policy(:resorce, models: [::OsFamily])
    end.to raise_error(ArgumentError, /unsupported event policy kind :resorce/)

    expect do
      operation.event_policy(
        :read,
        models: [::OsFamily],
        reason: 'invalid operation policy spec',
        atomic: false
      )
    end.to raise_error(ArgumentError, /read event policy does not capture models/)

    expect do
      policies.register_external(
        'spec.invalid_atomic_policy',
        kind: :transaction_chain,
        reason: 'invalid external policy spec',
        atomic: true
      )
    end.to raise_error(ArgumentError, /transaction_chain event policy must be non-atomic/)

    expect do
      policies.register_external(
        'spec.invalid_resource_policy',
        kind: :resource,
        atomic: false
      )
    end.to raise_error(ArgumentError, /resource event policy requires at least one model/)
  end

  it 'validates model event redactions during catalog finalization' do
    original_fields = Event.event_redacted_fields
    Event.instance_variable_set(
      :@event_redacted_fields,
      (original_fields + ['missing_from_events']).freeze
    )

    expect do
      described_class.send(:finalize_catalog!)
    end.to raise_error(
      ArgumentError,
      /Event\.event_redact contains non-auditable model attributes: missing_from_events/
    )
  ensure
    Event.instance_variable_set(:@event_redacted_fields, original_fields)
    described_class.send(:finalize_catalog!) if original_fields
  end

  it 'validates resource event redactions during catalog finalization' do
    declarations = described_class.instance_variable_get(:@declarations)
    index = declarations.index do |declaration|
      declaration.resource_class == VpsAdmin::API::Resources::User
    end
    original = declarations.fetch(index)
    declarations[index] = described_class::Declaration.new(
      **original.to_h,
      redact: (original.redact + ['missing_from_users']).freeze
    )

    expect do
      described_class.send(:finalize_catalog!)
    end.to raise_error(
      ArgumentError,
      /resource_events for .*User.*non-auditable model attributes: missing_from_users/
    )
  ensure
    declarations[index] = original if declarations && index && original
    described_class.send(:finalize_catalog!) if original
  end

  it 'accepts repeated external policies only when they are identical' do
    policies = VpsAdmin::API::Events::ActionPolicies
    name = 'spec.external_policy'
    attributes = {
      kind: :read,
      reason: 'architecture spec',
      atomic: false
    }

    first = policies.register_external(name, **attributes)

    expect(policies.register_external(name, **attributes)).to equal(first)
    expect do
      policies.register_external(
        name,
        kind: :internal_state,
        reason: 'conflicting architecture spec',
        atomic: false
      )
    end.to raise_error(ArgumentError, /conflicts with its existing declaration/)
  ensure
    policies.instance_variable_get(:@external)&.delete(name) if policies && name
  end

  it 'maps every generic blocking action to its target model and CRUD intent' do
    ApiAppHelper.app_instance

    walk_resource = lambda do |resource|
      actions = []
      resource.actions { |action| actions << action }
      resource.resources { |child| actions.concat(walk_resource.call(child)) }
      actions
    end
    policies = VpsAdmin::API::Events::ActionPolicies
    actions =
      HaveAPI.get_version_resources(VpsAdmin::API::Resources, '7.0').flat_map do |resource|
        walk_resource.call(resource)
      end
    generic_blocking = actions.select do |action|
      action.blocking && policies.for(action)&.kind == :transaction_chain
    end
    blocking = generic_blocking.select(&:model)

    expect(blocking).not_to be_empty
    blocking.each do |action|
      policy = policies.for(action)
      model_name = action.model&.base_class&.name

      expect(policy.models).to eq([model_name]), action.name
      expect(policy).to be_records_transaction_chain_resources

      intent =
        if action <= HaveAPI::Actions::Default::Create
          :created
        elsif action <= HaveAPI::Actions::Default::Update
          :updated
        elsif action <= HaveAPI::Actions::Default::Delete
          :deleted
        end

      expect(policy.resource_action).to eq(intent), action.name
    end

    generic_blocking.reject(&:model).each do |action|
      expect(policies.for(action)).to have_attributes(
        models: [],
        resource_action: nil
      )
    end
  end

  it 'records resources for blocking actions with synchronous mutation paths' do
    policies = VpsAdmin::API::Events::ActionPolicies
    action_plugins = {
      'VpsAdmin::API::Resources::OutageUpdate::Create' => :outage_reports
    }
    expected = {
      'VpsAdmin::API::Resources::SecurityAdvisory::Publish' =>
        %w[SecurityAdvisory SecurityAdvisoryUser SecurityAdvisoryVps],
      'VpsAdmin::API::Resources::SecurityAdvisoryUpdate::Create' =>
        %w[SecurityAdvisory SecurityAdvisoryTranslation SecurityAdvisoryUpdate],
      'VpsAdmin::API::Resources::OutageUpdate::Create' =>
        %w[Outage OutageExport OutageTranslation OutageUpdate OutageUser OutageVps],
      'VpsAdmin::API::Resources::IncidentReport::Create' =>
        %w[IncidentReport],
      'VpsAdmin::API::Resources::User::Update' =>
        %w[User]
    }

    expected.each do |action_name, models|
      action = policy_constant(action_name, plugin: action_plugins[action_name])
      next unless action

      policy = policies.for(action)

      expect(policy).to have_attributes(
        kind: :resource,
        models:
      )
    end
  end

  it 'classifies every operation entry point' do
    operation_classes = ObjectSpace.each_object(Class).select do |klass|
      klass < VpsAdmin::API::Operations::Base &&
        klass.name&.start_with?('VpsAdmin::API::Operations::')
    end
    missing = operation_classes.reject do |operation|
      VpsAdmin::API::Events::ActionPolicies.for_operation(operation)
    end

    expect(missing).to be_empty,
                       "Unclassified operations:\n#{missing.map(&:name).sort.join("\n")}"

    policies = VpsAdmin::API::Events::ActionPolicies
    %w[
      VpsAdmin::API::Operations::User::Login
      VpsAdmin::API::Operations::UserSession::NewBasicLogin
      VpsAdmin::API::Operations::UserSession::ResumeOAuth2
      VpsAdmin::API::Operations::UserSession::ResumeToken
    ].each do |operation_name|
      expect(policies.for_operation(operation_name.constantize)).to have_attributes(
        kind: :internal_state,
        reason: include('bookkeeping')
      )
    end
  end

  it 'classifies and installs all non-action HTTP mutation boundaries' do
    policies = VpsAdmin::API::Events::ActionPolicies
    oauth2_config = VpsAdmin::API::Authentication::OAuth2Config
    notifications = VpsAdmin::API::Notifications

    expect(policies.external_policies.keys).to contain_exactly(
      'notifications.sms_callback',
      'oauth2.authorize_get',
      'oauth2.authorize_post',
      'oauth2.issue_tokens',
      'oauth2.refresh_tokens',
      'oauth2.revoke',
      'webauthn.registration_new'
    )
    expect(policies.external_policy('webauthn.registration_new').kind).to eq(:read)
    expect(
      policies.external_policies.slice(
        'oauth2.authorize_get',
        'oauth2.authorize_post',
        'oauth2.issue_tokens',
        'oauth2.refresh_tokens',
        'oauth2.revoke'
      ).values
    ).to all(be_records_resources)
    expect(
      policies.external_policies.slice(
        'oauth2.authorize_get',
        'oauth2.authorize_post',
        'oauth2.issue_tokens',
        'oauth2.refresh_tokens',
        'oauth2.revoke'
      ).values
    ).to all(have_attributes(atomic: true))
    expect(policies.external_policy('notifications.sms_callback')).to have_attributes(
      kind: :internal_state,
      reason: include('feedback event')
    )
    expect(policies.external_policy_owners.keys).to contain_exactly(
      oauth2_config,
      notifications
    )

    oauth2_mappings = oauth2_config.external_event_policy_methods
    oauth2_execution = policies.external_policy_execution(oauth2_config)

    expect(oauth2_mappings.values).to contain_exactly(
      'oauth2.authorize_get',
      'oauth2.authorize_post',
      'oauth2.issue_tokens',
      'oauth2.refresh_tokens',
      'oauth2.revoke'
    )
    expect(policies.external_policies.keys.grep(/\Aoauth2\./))
      .to match_array(oauth2_mappings.values)
    expect(oauth2_execution.external_event_policy_methods).to eq(oauth2_mappings)
    expect(oauth2_execution.instance_methods(false)).to match_array(oauth2_mappings.keys)
    expect(VpsAdmin::API::Authentication::OAuth2Config.ancestors)
      .to include(oauth2_execution)

    notification_mappings = notifications.external_event_policy_methods
    notification_execution = policies.external_policy_execution(notifications)

    expect(notification_mappings).to eq(
      apply_sms_gateway_callback!: 'notifications.sms_callback'
    )
    expect(policies.external_policies.keys.grep(/\Anotifications\./))
      .to match_array(notification_mappings.values)
    expect(notification_execution.external_event_policy_methods)
      .to eq(notification_mappings)
    expect(notification_execution.instance_methods(false))
      .to match_array(notification_mappings.keys)
    expect(notifications.singleton_class.ancestors).to include(notification_execution)
  end

  it 'installs registered external policy owners during finalization' do
    policies = VpsAdmin::API::Events::ActionPolicies
    owner = Class.new do
      def callback; end
    end
    mappings = { callback: 'oauth2.authorize_get' }.freeze

    policies.register_external_owner(owner, mappings:)

    expect { policies.external_policy_execution(owner) }.to raise_error(KeyError)
    expect { policies.finalize! }.not_to raise_error

    execution = policies.external_policy_execution(owner)
    expect(owner.ancestors).to include(execution)

    expect { policies.finalize! }.not_to raise_error
    expect(policies.external_policy_execution(owner)).to equal(execution)
    expect(owner.ancestors.count { |ancestor| ancestor.equal?(execution) }).to eq(1)
  ensure
    policies.instance_variable_get(:@external_policy_owners)&.delete(owner) if policies && owner
    policies.instance_variable_get(:@external_policy_execution)&.delete(owner) if policies && owner
  end

  it 'rejects invalid and conflicting external policy owner mappings atomically' do
    policies = VpsAdmin::API::Events::ActionPolicies
    missing_method = Class.new do
      def self.external_event_policy_methods
        { missing_callback: 'oauth2.authorize_get' }
      end
    end
    missing_policy = Class.new do
      def self.external_event_policy_methods
        { callback: 'spec.missing_external_policy' }
      end

      def callback; end
    end
    owner = Class.new do
      def callback; end
    end
    mappings = { callback: 'oauth2.authorize_get' }.freeze

    expect do
      policies.register_external_owner(
        missing_method,
        mappings: missing_method.external_event_policy_methods
      )
    end
      .to raise_error(ArgumentError, /does not implement.*missing_callback/)
    expect do
      policies.register_external_owner(
        missing_policy,
        mappings: missing_policy.external_event_policy_methods
      )
    end
      .to raise_error(ArgumentError, /undeclared external event policies.*spec\.missing/)

    registration = policies.register_external_owner(owner, mappings:)
    expect(policies.register_external_owner(owner, mappings:)).to equal(registration)
    expect do
      policies.register_external_owner(
        owner,
        mappings: { callback: 'oauth2.authorize_post' }
      )
    end.to raise_error(ArgumentError, /conflicts with its existing declaration/)

    expect(policies.external_policy_owners.fetch(owner)).to equal(registration)
    expect(policies.external_policy_owners).not_to have_key(missing_method)
    expect(policies.external_policy_owners).not_to have_key(missing_policy)
  ensure
    policies.instance_variable_get(:@external_policy_owners)&.delete(owner) if policies && owner
  end

  it 'registers only real callback-bypassing delete cascades' do
    model_plugins = {
      'MonitoredEvent' => :monitoring,
      'NewsLog' => :newslog
    }

    VpsAdmin::API::Events::ActionPolicies.delete_cascades.each do |model_name, associations|
      model = policy_constant(model_name, plugin: model_plugins[model_name])
      next unless model

      associations.each do |association|
        reflection = model.reflect_on_association(association)
        expect(reflection).not_to be_nil,
                                  "#{model_name}.#{association} is not an association"
        message = "#{model_name}.#{association} does not bypass destroy callbacks"
        expect(reflection.options[:dependent]).to(
          be_in(%i[delete delete_all]),
          message
        )
      end
    end
  end

  it 'captures nested delete cascades with their owner before rows disappear' do
    user = SpecSeed.user
    parent = EventRoute.create!(
      user:,
      label: 'Audit parent route',
      position: 0
    )
    child = EventRoute.create!(
      user:,
      parent_event_route: parent,
      label: 'Audit child route',
      position: 0
    )
    matcher = child.event_route_matchers.create!(
      field: 'severity',
      operator: '==',
      value: 'info'
    )
    policy = VpsAdmin::API::Events::ActionPolicies::Policy.new(
      kind: :resource,
      models: %w[EventRoute],
      reason: nil,
      atomic: true
    )

    with_current_context(user:) do
      VpsAdmin::API::Events::ActionPolicies.capture(policy) do
        parent.destroy!
      end
    end

    child_event = Event.where(
      event_type: 'event_route.deleted',
      source_class: 'EventRoute',
      source_id: child.id
    ).sole
    matcher_event = Event.where(
      event_type: 'event_route_matcher.deleted',
      source_class: 'EventRouteMatcher',
      source_id: matcher.id
    ).sole
    expect(child_event.user).to eq(user)
    expect(matcher_event.user).to eq(user)
  end

  it 'rolls back an explicitly captured bulk write and its event' do
    os_family = OsFamily.create!(
      label: "Bulk audit rollback #{Process.pid}",
      description: 'before'
    )
    policy = VpsAdmin::API::Events::ActionPolicies::Policy.new(
      kind: :resource,
      models: %w[OsFamily],
      reason: nil,
      atomic: true
    )

    expect do
      VpsAdmin::API::Events::ActionPolicies.capture(policy) do
        OsFamily.where(id: os_family.id).update_all(description: 'after')
        VpsAdmin::API::Events::ActionPolicies.record(
          :updated,
          os_family,
          changed_fields: %i[description]
        )
        raise 'bulk operation failed'
      end
    end.to raise_error('bulk operation failed')

    expect(os_family.reload.description).to eq('before')
    expect(
      Event.where(
        event_type: 'os_family.updated',
        source_class: 'OsFamily',
        source_id: os_family.id
      )
    ).to be_empty
  end

  it 'discards callbacks recorded by a rolled-back inner transaction' do
    os_family = OsFamily.create!(
      label: "Inner rollback audit #{Process.pid}",
      description: 'before'
    )
    policy = VpsAdmin::API::Events::ActionPolicies::Policy.new(
      kind: :resource,
      models: %w[OsFamily],
      reason: nil,
      atomic: false,
      emit_on_failure: true
    )

    expect do
      VpsAdmin::API::Events::ActionPolicies.capture(policy) do
        OsFamily.transaction(requires_new: true) do
          os_family.update!(description: 'rolled back')
          raise 'inner operation failed'
        end
      end
    end.to raise_error('inner operation failed')

    expect(os_family.reload.description).to eq('before')
    expect(
      Event.where(
        event_type: 'os_family.updated',
        source_class: 'OsFamily',
        source_id: os_family.id
      )
    ).to be_empty
  end

  it 'emits only fields whose observed mutation remains committed' do
    os_family = OsFamily.create!(
      label: "Mixed rollback audit #{Process.pid}",
      description: 'before'
    )
    policy = VpsAdmin::API::Events::ActionPolicies::Policy.new(
      kind: :resource,
      models: %w[OsFamily],
      reason: nil,
      atomic: true
    )

    VpsAdmin::API::Events::ActionPolicies.capture(policy) do
      OsFamily.transaction(requires_new: true) do
        os_family.update!(description: 'rolled back')
        raise ActiveRecord::Rollback
      end

      os_family.reload.update!(label: "Committed label #{Process.pid}")
    end

    expect(os_family.reload.description).to eq('before')
    event = Event.where(
      event_type: 'os_family.updated',
      source_class: 'OsFamily',
      source_id: os_family.id
    ).sole
    expect(event.parameters['changed_fields']).to eq(['label'])
  end

  it 'suppresses fields restored to their pre-action value' do
    os_family = OsFamily.create!(
      label: "Reverted field audit #{Process.pid}",
      description: 'before'
    )
    policy = VpsAdmin::API::Events::ActionPolicies::Policy.new(
      kind: :resource,
      models: %w[OsFamily],
      reason: nil,
      atomic: true
    )

    VpsAdmin::API::Events::ActionPolicies.capture(policy) do
      os_family.update!(description: 'temporary')
      os_family.update!(description: 'before')
      os_family.update!(label: "Committed label #{Process.pid}")
    end

    event = Event.where(
      event_type: 'os_family.updated',
      source_class: 'OsFamily',
      source_id: os_family.id
    ).sole
    expect(event.parameters['changed_fields']).to eq(['label'])
  end

  it 'keeps a create recorded before a rolled-back delete' do
    policy = VpsAdmin::API::Events::ActionPolicies::Policy.new(
      kind: :resource,
      models: %w[OsFamily],
      reason: nil,
      atomic: true
    )
    os_family = nil

    VpsAdmin::API::Events::ActionPolicies.capture(policy) do
      os_family = OsFamily.create!(label: "Create delete rollback #{Process.pid}")

      OsFamily.transaction(requires_new: true) do
        os_family.destroy!
        raise ActiveRecord::Rollback
      end
    end

    expect(OsFamily.where(id: os_family.id)).to exist
    event = Event.where(
      event_type: 'os_family.created',
      source_class: 'OsFamily',
      source_id: os_family.id
    ).sole
    expect(event.parameters['changed_fields']).to include('label')
  end

  it 'does not emit a create for an object deleted in the same action' do
    policy = VpsAdmin::API::Events::ActionPolicies::Policy.new(
      kind: :resource,
      models: %w[OsFamily],
      reason: nil,
      atomic: true
    )
    os_family = nil

    VpsAdmin::API::Events::ActionPolicies.capture(policy) do
      os_family = OsFamily.create!(label: "Transient create audit #{Process.pid}")
      os_family.destroy!
    end

    expect(OsFamily.where(id: os_family.id)).not_to exist
    expect(
      Event.where(
        event_type: 'os_family.created',
        source_class: 'OsFamily',
        source_id: os_family.id
      )
    ).to be_empty
  end

  it 'reads fields from partial rows through raw attribute access' do
    model = Class.new(ApplicationRecord) do
      self.table_name = 'os_families'

      def description = 'derived value'
    end
    stub_const('AuditSpecOsFamily', model)
    os_family = OsFamily.create!(
      label: "Partial row audit #{Process.pid}",
      description: 'before'
    )
    partial = model.select(:id, :description).find(os_family.id)

    partial[:description] = 'after'
    partial.save!(validate: false, touch: false)
    payload = described_class.payload_for(
      :updated,
      partial,
      changed_fields: %i[description]
    )

    expect(os_family.reload[:description]).to eq('after')
    expect(payload.fetch(:changed_fields)).to eq(['description'])
    expect(payload.dig(:changes, 'description')).to eq(
      'old' => { 'kind' => 'value', 'value' => 'before' },
      'new' => { 'kind' => 'value', 'value' => 'after' }
    )
  end

  it 'captures secondary public models without applying the target CRUD intent' do
    policies = VpsAdmin::API::Events::ActionPolicies
    policy = policies::Policy.new(
      kind: :transaction_chain,
      models: %w[OsFamily],
      reason: 'mixed synchronous blocking action',
      atomic: false,
      resource_action: :created
    )
    recorder = policies::Recorder.new(policy)
    os_family = nil

    policies.with_recorder(recorder) do
      os_family = OsFamily.create!(
        label: "Mixed blocking action #{SecureRandom.hex(4)}"
      )
      SpecSeed.node.update!(active: !SpecSeed.node.active)
    end
    recorder.emit!

    expect(
      Event.where(
        event_type: 'os_family.created',
        source_class: 'OsFamily',
        source_id: os_family.id
      )
    ).to exist
    expect(
      Event.where(
        event_type: 'node.updated',
        source_class: 'Node',
        source_id: SpecSeed.node.id
      )
    ).to exist
    expect(
      Event.where(
        event_type: 'node.created',
        source_class: 'Node',
        source_id: SpecSeed.node.id
      )
    ).to be_empty
  end

  it 'captures an OAuth callback and deduplicates its nested operation' do
    operation = Class.new(VpsAdmin::API::Operations::Base) do
      def run(label:)
        ::OsFamily.create!(label:).tap do |os_family|
          os_family.update!(description: 'Created inside OAuth callback')
        end
      end
    end
    stub_const('VpsAdmin::API::Operations::AuditSpecOAuthMutation', operation)
    operation.event_policy :resource, models: [::OsFamily]

    boundary_base = Class.new do
      def handle_post_authorize(operation:, label:, marker:, fail_after: false)
        record = operation.run(label:)
        raise 'OAuth callback failed' if fail_after

        [record, marker]
      end
    end
    boundary_base.define_singleton_method(:external_event_policy_methods) do
      { handle_post_authorize: 'oauth2.authorize_post' }
    end
    execution = VpsAdmin::API::Events::ActionPolicies::ExternalPolicyExecution.build(boundary_base)
    boundary = Class.new(boundary_base) do
      prepend execution
    end
    label = "OAuth operation capture #{Process.pid}"
    marker = Object.new

    os_family, returned_marker = boundary.new.handle_post_authorize(
      operation:,
      label:,
      marker:,
      fail_after: false
    )

    expect(returned_marker).to equal(marker)
    expect(os_family).to be_persisted

    events = Event.where(
      event_type: 'os_family.created',
      source_class: 'OsFamily',
      source_id: os_family.id
    )
    expect(events.count).to eq(1)
    expect(events.sole.parameters['changed_fields'])
      .to contain_exactly('description', 'label')
    expect(
      Event.where(
        event_type: 'os_family.updated',
        source_class: 'OsFamily',
        source_id: os_family.id
      )
    ).to be_empty

    failed_label = "#{label} failed"
    event_count = Event.where(
      event_type: 'os_family.created',
      source_class: 'OsFamily'
    ).count
    expect do
      boundary.new.handle_post_authorize(
        operation:,
        label: failed_label,
        marker:,
        fail_after: true
      )
    end.to raise_error('OAuth callback failed')
    expect(OsFamily.where(label: failed_label)).to be_empty
    expect(
      Event.where(
        event_type: 'os_family.created',
        source_class: 'OsFamily'
      ).count
    ).to eq(event_count)
  end

  it 'ignores resource actions that the public catalog does not publish' do
    policies = VpsAdmin::API::Events::ActionPolicies
    device = create_user_device!(user: SpecSeed.user, known: true)

    expect do
      policies.capture(policies.external_policy('oauth2.authorize_post')) do
        device.update!(last_seen_at: Time.now)
      end
    end.not_to change(
      Event.where(
        event_type: 'user_known_device.updated',
        source_class: 'UserDevice',
        source_id: device.id
      ),
      :count
    )
  end

  it 'rolls back records and events when an atomic operation fails' do
    operation = Class.new(VpsAdmin::API::Operations::Base) do
      def run(label:)
        ::OsFamily.create!(label:)
        raise 'operation failed'
      end
    end
    stub_const('VpsAdmin::API::Operations::AuditSpecFailure', operation)
    operation.event_policy :resource, models: [::OsFamily]
    label = "Audit operation rollback #{Process.pid}"
    event_count = Event.where(
      event_type: 'os_family.created',
      source_class: 'OsFamily'
    ).count

    expect { operation.run(label:) }.to raise_error('operation failed')
    expect(OsFamily.where(label:)).to be_empty
    expect(
      Event.where(event_type: 'os_family.created', source_class: 'OsFamily').count
    ).to eq(event_count)
  end
end
