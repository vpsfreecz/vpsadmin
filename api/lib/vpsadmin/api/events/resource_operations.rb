module VpsAdmin::API::Events::ResourceOperations
  ACTIONS = %w[created updated deleted].freeze
  IGNORED_CHANGED_FIELDS = %w[
    created_at
    id
    lock_version
    updated_at
  ].freeze
  INFER_RELATION = Object.new.freeze

  @owner_resolvers = {}
  @vps_resolvers = {}

  module_function

  def emit!(
    action,
    object,
    owner: INFER_RELATION,
    vps: INFER_RELATION,
    changed_fields: [],
    occurred_at: nil
  )
    action = action.to_s
    raise ArgumentError, "unsupported resource event action #{action.inspect}" unless ACTIONS.include?(action)

    actor = ::User.current
    session = ::UserSession.current
    resource_type = object.class.base_class.name
    resource_id = object.id
    vps = related_vps(object) if vps.equal?(INFER_RELATION)
    owner = resource_owner(object, vps:) if owner.equal?(INFER_RELATION)

    VpsAdmin::API::Events.emit!(
      "resource.#{action}",
      user: owner,
      vps:,
      source_class: resource_type,
      source_id: resource_id,
      subject: "#{resource_type} ##{resource_id} #{action}",
      summary: resource_summary(
        action,
        resource_type,
        resource_id,
        actor:
      ),
      payload: {
        resource_type:,
        resource_id:,
        action:,
        actor_user_id: actor&.id,
        actor_user_login: actor&.login,
        admin_user_id: session&.admin_id,
        user_session_id: session&.id,
        changed_fields: Array(changed_fields).map(&:to_s).uniq.sort
      }.compact,
      ip_addr: session&.client_ip_addr || session&.api_ip_addr,
      occurred_at:,
      persist: :always
    )
  end

  def created!(object, **)
    emit!(:created, object, **)
  end

  def updated!(object, **)
    emit!(:updated, object, **)
  end

  def deleted!(object, **)
    emit!(:deleted, object, **)
  end

  def resource_owner(object, vps:)
    return vps.user if vps

    resolver = @owner_resolvers[object.class.base_class.name]
    resolver&.call(object)
  end

  def related_vps(object)
    resolver = @vps_resolvers[object.class.base_class.name]
    resolver&.call(object)
  end

  def register_owner(*class_names, via: nil, &block)
    resolver = block || association_resolver(via)
    class_names.each { |class_name| @owner_resolvers[class_name.to_s] = resolver }
  end

  def register_vps(*class_names, via: nil, &block)
    resolver = block || association_resolver(via)
    class_names.each { |class_name| @vps_resolvers[class_name.to_s] = resolver }
  end

  def changed_fields_for(object)
    object.saved_changes.keys.map(&:to_s).reject do |field|
      IGNORED_CHANGED_FIELDS.include?(field)
    end
  end

  def association_resolver(path)
    steps = Array(path)
    raise ArgumentError, 'association path is required' if steps.empty?

    lambda do |object|
      steps.reduce(object) do |value, association|
        break if value.nil?

        value.public_send(association)
      end
    end
  end

  def resource_summary(action, resource_type, resource_id, actor:)
    actor_label =
      if actor
        "#{actor.login} (user ##{actor.id})"
      else
        'System'
      end

    "#{actor_label} #{action} #{resource_type} ##{resource_id}"
  end
end

# Resource ownership is intentionally declared instead of inferred from whatever
# association methods a model happens to expose. Unknown resource classes are
# system-owned and are therefore visible only to administrators.
VpsAdmin::API::Events::ResourceOperations.register_owner('User') { |user| user }

VpsAdmin::API::Events::ResourceOperations.register_owner(
  'ClusterResourcePackage',
  'AuthToken',
  'Dataset',
  'DnsRecord',
  'DnsTsigKey',
  'DnsZone',
  'EnvironmentUserConfig',
  'EventRoute',
  'EventTimeInterval',
  'Export',
  'IncidentReport',
  'IpAddress',
  'IpAddressAssignment',
  'MetricsAccessToken',
  'MigrationPlan',
  'MonitoredEvent',
  'Network',
  'NotificationReceiver',
  'NotificationTarget',
  'Oauth2Authorization',
  'OutageExport',
  'OutageHandler',
  'OutageUser',
  'OutageVps',
  'SecurityAdvisoryUser',
  'SecurityAdvisoryVps',
  'SingleSignOn',
  'SnapshotDownload',
  'UserAccount',
  'UserClusterResourcePackage',
  'UserDevice',
  'UserNamespace',
  'UserNotificationDeliveryMethod',
  'UserNotificationRateLimit',
  'UserPayment',
  'UserPublicKey',
  'UserRequest',
  'UserSession',
  'UserTotpDevice',
  'Vps',
  'VpsConsole',
  'VpsMigration',
  'VpsUserData',
  'WebauthnChallenge',
  'WebauthnCredential',
  'WebuiUserSetting',
  via: :user
)

VpsAdmin::API::Events::ResourceOperations.register_owner('Token') do |token|
  owner = token.owner
  next if owner.nil?

  operations = VpsAdmin::API::Events::ResourceOperations
  operations.resource_owner(owner, vps: operations.related_vps(owner))
end

VpsAdmin::API::Events::ResourceOperations.register_owner('MaintenanceLock') do |lock|
  klass = lock.class_name.safe_constantize
  target =
    if klass && klass < ::ApplicationRecord && lock.row_id
      klass.find_by(id: lock.row_id)
    end

  if target
    operations = VpsAdmin::API::Events::ResourceOperations
    operations.resource_owner(target, vps: operations.related_vps(target))
  end
end

VpsAdmin::API::Events::ResourceOperations.register_owner(
  'DatasetExpansion',
  'Mount',
  'NetworkInterface',
  'OomPrevention',
  'OomReport',
  'OomReportCounter',
  'VpsFeature',
  'VpsMaintenanceWindow',
  'VpsSshHostKey',
  'VpsStatus',
  via: %i[vps user]
)

VpsAdmin::API::Events::ResourceOperations.register_owner(
  'DatasetInPool',
  'Snapshot',
  via: %i[dataset user]
)

VpsAdmin::API::Events::ResourceOperations.register_owner(
  'DnsServerZone',
  'DnsZoneTransfer',
  'DnssecRecord',
  via: %i[dns_zone user]
)

VpsAdmin::API::Events::ResourceOperations.register_owner(
  'EventRouteMatcher',
  'EventRouteTimeInterval',
  via: %i[event_route user]
)

VpsAdmin::API::Events::ResourceOperations.register_owner(
  'EventDelivery',
  via: %i[event user]
)
VpsAdmin::API::Events::ResourceOperations.register_owner(
  'EventDeliveryAttempt',
  via: %i[event_delivery event user]
)

VpsAdmin::API::Events::ResourceOperations.register_owner(
  'ExportHost',
  via: %i[export user]
)

VpsAdmin::API::Events::ResourceOperations.register_owner(
  'NotificationReceiverAction',
  'NotificationReceiverTarget',
  via: %i[notification_receiver user]
)

VpsAdmin::API::Events::ResourceOperations.register_owner(
  'UserNamespaceBlock',
  'UserNamespaceMap',
  via: %i[user_namespace user]
)

VpsAdmin::API::Events::ResourceOperations.register_owner(
  'UserNamespaceMapEntry',
  via: %i[user_namespace_map user_namespace user]
)

VpsAdmin::API::Events::ResourceOperations.register_vps('Vps') { |vps| vps }
VpsAdmin::API::Events::ResourceOperations.register_vps('Token') do |token|
  owner = token.owner
  next if owner.nil?

  VpsAdmin::API::Events::ResourceOperations.related_vps(owner)
end
VpsAdmin::API::Events::ResourceOperations.register_vps(
  'EventDelivery',
  via: %i[event vps]
)
VpsAdmin::API::Events::ResourceOperations.register_vps(
  'EventDeliveryAttempt',
  via: %i[event_delivery event vps]
)
VpsAdmin::API::Events::ResourceOperations.register_vps('MaintenanceLock') do |lock|
  klass = lock.class_name.safe_constantize
  target =
    if klass && klass < ::ApplicationRecord && lock.row_id
      klass.find_by(id: lock.row_id)
    end

  VpsAdmin::API::Events::ResourceOperations.related_vps(target) if target
end
VpsAdmin::API::Events::ResourceOperations.register_vps(
  'DatasetExpansion',
  'Mount',
  'NetworkInterface',
  'OomPrevention',
  'OomReport',
  'OomReportCounter',
  'VpsFeature',
  'VpsMaintenanceWindow',
  'VpsSshHostKey',
  'VpsStatus',
  via: :vps
)

VpsAdmin::API::Events.define do
  {
    'resource.created' => 'Resource created',
    'resource.updated' => 'Resource updated',
    'resource.deleted' => 'Resource deleted'
  }.each do |event_name, label|
    action = event_name.delete_prefix('resource.')
    changed_fields_example =
      case action
      when 'created'
        %w[description label]
      when 'updated'
        %w[label]
      else
        []
      end

    event event_name,
          label:,
          category: 'resource',
          severity: :info,
          roles: %i[account admin],
          default_routed: false,
          examples: {
            subject: "OsFamily #42 #{action}",
            summary: "alice (user #123) #{action} OsFamily #42"
          } do
      fields VpsAdmin::API::Events::Core::OPERATION_RESULT_FIELDS
      fields(
        resource_type: {
          description: 'ActiveRecord class of the affected resource',
          type: :string,
          example: 'OsFamily'
        },
        resource_id: {
          description: 'ID of the affected resource',
          type: :integer,
          example: 42
        },
        action: {
          description: 'Completed create, update or delete action',
          type: :string,
          choices: VpsAdmin::API::Events::ResourceOperations::ACTIONS,
          example: action
        },
        actor_user_id: {
          description: 'ID of the user who performed the action',
          type: :integer,
          example: 123
        },
        actor_user_login: {
          description: 'Login of the user who performed the action',
          type: :string,
          example: 'alice'
        },
        admin_user_id: {
          description: 'ID of the administrator behind an impersonated session',
          type: :integer,
          example: 7
        },
        user_session_id: {
          description: 'ID of the user session associated with the event',
          type: :integer,
          example: 456
        },
        changed_fields: {
          description: 'Names of persisted fields changed by the operation',
          type: :string_list,
          example: changed_fields_example
        }
      )
    end
  end
end

require_relative 'action_policies'
