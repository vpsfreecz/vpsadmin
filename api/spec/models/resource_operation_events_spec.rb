# frozen_string_literal: true

require 'spec_helper'

RSpec.describe VpsAdmin::API::Events::ResourceOperations do
  def policy_constant(name, plugin: nil)
    klass = name.safe_constantize
    return klass if klass
    return if plugin && !SpecPlugins.enabled?(plugin)

    raise NameError, "event policy constant #{name} is not loaded"
  end

  it 'records a user-owned resource mutation without copying submitted values' do
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
    expect(event.event_type).to eq('resource.updated')
    expect(event.source_class).to eq('User')
    expect(event.source_id).to eq(SpecSeed.user.id)
    expect(event.parameters).to include(
      'resource_type' => 'User',
      'resource_id' => SpecSeed.user.id,
      'action' => 'updated',
      'actor_user_id' => SpecSeed.user.id,
      'actor_user_login' => SpecSeed.user.login,
      'changed_fields' => %w[login password]
    )
    expect(event.payload_json).not_to include(SpecSeed::PASSWORD)
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
      'resource_type' => 'Node',
      'resource_id' => SpecSeed.node.id,
      'action' => 'created',
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

  it 'publishes all generic resource event types in the event catalog' do
    expect(described_class::ACTIONS.map { |action| "resource.#{action}" })
      .to all(satisfy { |event_type| VpsAdmin::API::Events.type_for(event_type) })
  end

  it 'classifies every mutating API action' do
    ApiAppHelper.app_instance

    walk_resource = lambda do |resource|
      actions = []
      resource.actions { |action| actions << action }
      resource.resources { |child| actions.concat(walk_resource.call(child)) }
      actions
    end

    actions =
      HaveAPI.get_version_resources(VpsAdmin::API::Resources, '7.0').flat_map do |resource|
        walk_resource.call(resource)
      end

    mutating = actions.select do |action|
      VpsAdmin::API::Events::ActionPolicies.mutating?(action)
    end
    missing = mutating.reject do |action|
      VpsAdmin::API::Events::ActionPolicies.for(action)
    end

    expect(missing).to be_empty,
                       "Unclassified mutating actions:\n#{missing.map(&:name).sort.join("\n")}"
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

    expect(VpsAdmin::API::Authentication::OAuth2Config.ancestors)
      .to include(policies::OAuth2Execution)
    expect(VpsAdmin::API::Notifications.singleton_class.ancestors)
      .to include(policies::NotificationCallbackExecution)
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
      event_type: 'resource.deleted',
      source_class: 'EventRoute',
      source_id: child.id
    ).sole
    matcher_event = Event.where(
      event_type: 'resource.deleted',
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
        event_type: 'resource.updated',
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
        event_type: 'resource.updated',
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
      event_type: 'resource.updated',
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
      event_type: 'resource.updated',
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
      event_type: 'resource.created',
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
        event_type: 'resource.created',
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
    policy = VpsAdmin::API::Events::ActionPolicies::Policy.new(
      kind: :resource,
      models: %w[AuditSpecOsFamily],
      reason: nil,
      atomic: true
    )
    partial = model.select(:id, :description).find(os_family.id)

    VpsAdmin::API::Events::ActionPolicies.capture(policy) do
      partial[:description] = 'after'
      partial.save!(validate: false, touch: false)
    end

    expect(os_family.reload[:description]).to eq('after')
    event = Event.where(
      event_type: 'resource.updated',
      source_class: 'AuditSpecOsFamily',
      source_id: os_family.id
    ).sole
    expect(event.parameters['changed_fields']).to eq(['description'])
  end

  it 'applies default CRUD intent only to the action target model' do
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
      recorder.allow_models(%w[Node])
      SpecSeed.node.update!(active: !SpecSeed.node.active)
    end
    recorder.emit!

    expect(
      Event.where(
        event_type: 'resource.created',
        source_class: 'OsFamily',
        source_id: os_family.id
      )
    ).to exist
    expect(
      Event.where(
        event_type: 'resource.updated',
        source_class: 'Node',
        source_id: SpecSeed.node.id
      )
    ).to exist
    expect(
      Event.where(
        event_type: 'resource.created',
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
    VpsAdmin::API::Events::ActionPolicies.register_operation(
      operation.name,
      kind: :resource,
      models: %w[OsFamily]
    )

    boundary_base = Class.new do
      def handle_post_authorize(operation:, label:, marker:, fail_after: false)
        record = operation.run(label:)
        raise 'OAuth callback failed' if fail_after

        [record, marker]
      end
    end
    boundary = Class.new(boundary_base) do
      prepend VpsAdmin::API::Events::ActionPolicies::OAuth2Execution
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
      event_type: 'resource.created',
      source_class: 'OsFamily',
      source_id: os_family.id
    )
    expect(events.count).to eq(1)
    expect(events.sole.parameters['changed_fields'])
      .to contain_exactly('description', 'label')
    expect(
      Event.where(
        event_type: 'resource.updated',
        source_class: 'OsFamily',
        source_id: os_family.id
      )
    ).to be_empty

    failed_label = "#{label} failed"
    event_count = Event.where(
      event_type: 'resource.created',
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
        event_type: 'resource.created',
        source_class: 'OsFamily'
      ).count
    ).to eq(event_count)
  end

  it 'rolls back records and events when an atomic operation fails' do
    operation = Class.new(VpsAdmin::API::Operations::Base) do
      def run(label:)
        ::OsFamily.create!(label:)
        raise 'operation failed'
      end
    end
    stub_const('VpsAdmin::API::Operations::AuditSpecFailure', operation)
    VpsAdmin::API::Events::ActionPolicies.register_operation(
      operation.name,
      kind: :resource,
      models: %w[OsFamily]
    )
    label = "Audit operation rollback #{Process.pid}"
    event_count = Event.where(
      event_type: 'resource.created',
      source_class: 'OsFamily'
    ).count

    expect { operation.run(label:) }.to raise_error('operation failed')
    expect(OsFamily.where(label:)).to be_empty
    expect(
      Event.where(event_type: 'resource.created', source_class: 'OsFamily').count
    ).to eq(event_count)
  end
end
