module VpsAdmin::API::Events::ResourceOperations
  ACTIONS = %w[created updated deleted].freeze
  SCHEMA_VERSION = 1
  MAX_INLINE_VALUE_BYTES = 4 * 1024
  MAX_PAYLOAD_BYTES = 48 * 1024
  IGNORED_CHANGED_FIELDS = %w[
    created_at
    id
    lock_version
    updated_at
  ].freeze
  RESOURCE_NAME_OVERRIDES = {
    'ChangeRequest' => 'request',
    'EnvironmentUserConfig' => 'user_environment_config',
    'Mount' => 'vps_mount',
    'Oauth2Client' => 'oauth2_client',
    'OutageExport' => 'export_outage',
    'OutageUser' => 'user_outage',
    'OutageVps' => 'vps_outage',
    'RegistrationRequest' => 'request',
    'SysConfig' => 'system_config',
    'UserDevice' => 'user_known_device',
    'UserPublicKey' => 'user_public_key',
    'UserRequest' => 'request',
    'UserTotpDevice' => 'user_totp_device',
    'Vps' => 'vps',
    'VpsConsole' => 'vps_console_token',
    'WebauthnCredential' => 'user_webauthn_credential'
  }.freeze
  TOPICS = %w[
    account
    dns
    incidents
    infrastructure
    mail
    monitoring
    network
    notifications
    operating_systems
    outages
    payments
    requests
    security
    storage
    system
    vps
  ].freeze
  TOPIC_LABELS = {
    'account' => 'Account',
    'dns' => 'DNS',
    'incidents' => 'Incidents',
    'infrastructure' => 'Infrastructure',
    'mail' => 'Mail',
    'monitoring' => 'Monitoring',
    'network' => 'Network',
    'notifications' => 'Notifications',
    'operating_systems' => 'Operating systems',
    'outages' => 'Outages',
    'payments' => 'Payments',
    'requests' => 'Requests',
    'security' => 'Security',
    'storage' => 'Storage',
    'system' => 'System',
    'vps' => 'VPS'
  }.freeze
  AUDIENCES = %i[account admin].freeze
  CatalogEntry = Data.define(
    :model_name,
    :api_resources,
    :actions,
    :topic,
    :audience,
    :logical_name
  )
  RESOURCE_CATALOG = [
    # Account and user configuration
    ['User', 'VpsAdmin::API::Resources::User', %w[created updated deleted],
     'account', :account],
    ['UserClusterResource', 'VpsAdmin::API::Resources::User::ClusterResource',
     %w[created], 'account', :account],
    ['EnvironmentUserConfig',
     'VpsAdmin::API::Resources::User::EnvironmentConfig', %w[updated],
     'account', :account],
    ['UserClusterResourcePackage',
     'VpsAdmin::API::Resources::UserClusterResourcePackage',
     %w[created updated deleted], 'account', :account],
    ['UserNamespaceMap', 'VpsAdmin::API::Resources::UserNamespaceMap',
     %w[created updated deleted], 'account', :account],
    ['UserNamespaceMapEntry',
     'VpsAdmin::API::Resources::UserNamespaceMap::Entry',
     %w[created updated deleted], 'account', :account],
    # DNS
    ['DnsRecord', 'VpsAdmin::API::Resources::DnsRecord',
     %w[created updated deleted], 'dns', :account],
    ['DnsTsigKey', 'VpsAdmin::API::Resources::DnsTsigKey',
     %w[created deleted], 'dns', :account],
    ['DnsZone', 'VpsAdmin::API::Resources::DnsZone',
     %w[created updated deleted], 'dns', :account],
    ['DnsZoneTransfer', 'VpsAdmin::API::Resources::DnsZoneTransfer',
     %w[created deleted], 'dns', :account],
    ['DnsServerZone', 'VpsAdmin::API::Resources::DnsServerZone',
     %w[created deleted], 'dns', :account],
    ['DnsResolver', 'VpsAdmin::API::Resources::DnsResolver',
     %w[created updated deleted], 'dns', :admin],
    ['DnsServer', 'VpsAdmin::API::Resources::DnsServer',
     %w[created updated deleted], 'dns', :admin],

    # Infrastructure
    ['ClusterResource', 'VpsAdmin::API::Resources::ClusterResource',
     %w[created updated], 'infrastructure', :admin],
    ['ClusterResourcePackage',
     'VpsAdmin::API::Resources::ClusterResourcePackage',
     %w[created updated deleted], 'infrastructure', :admin],
    ['ClusterResourcePackageItem',
     'VpsAdmin::API::Resources::ClusterResourcePackage::Item',
     %w[created updated deleted], 'infrastructure', :admin],
    ['DefaultObjectClusterResource',
     'VpsAdmin::API::Resources::DefaultObjectClusterResource',
     %w[created updated deleted], 'infrastructure', :admin],
    ['Environment', 'VpsAdmin::API::Resources::Environment',
     %w[created updated], 'infrastructure', :admin],
    ['Location', 'VpsAdmin::API::Resources::Location',
     %w[created updated], 'infrastructure', :admin],
    ['MigrationPlan', 'VpsAdmin::API::Resources::MigrationPlan',
     %w[created updated deleted], 'infrastructure', :admin],
    ['VpsMigration',
     'VpsAdmin::API::Resources::MigrationPlan::VpsMigration',
     %w[created updated], 'infrastructure', :admin],
    ['Node', 'VpsAdmin::API::Resources::Node',
     %w[created updated], 'infrastructure', :admin],
    ['NodeTransferConnection',
     'VpsAdmin::API::Resources::NodeTransferConnection',
     %w[created updated deleted], 'infrastructure', :admin],
    ['Pool', 'VpsAdmin::API::Resources::Pool', %w[created],
     'infrastructure', :admin],

    # Networking
    ['HostIpAddress', 'VpsAdmin::API::Resources::HostIpAddress',
     %w[created updated deleted], 'network', :admin],
    ['IpAddress', 'VpsAdmin::API::Resources::IpAddress',
     %w[created updated], 'network', :account],
    ['LocationNetwork', 'VpsAdmin::API::Resources::LocationNetwork',
     %w[created updated deleted], 'network', :admin],
    ['Network', 'VpsAdmin::API::Resources::Network',
     %w[created updated], 'network', :admin],
    ['NetworkInterface', 'VpsAdmin::API::Resources::NetworkInterface',
     %w[updated], 'network', :account],

    # Storage
    ['Dataset', 'VpsAdmin::API::Resources::Dataset',
     %w[created updated deleted], 'storage', :account],
    ['DatasetInPoolPlan', 'VpsAdmin::API::Resources::Dataset::Plan',
     %w[created deleted], 'storage', :account],
    ['Snapshot', 'VpsAdmin::API::Resources::Dataset::Snapshot',
     %w[created deleted], 'storage', :account],
    ['DatasetExpansion', 'VpsAdmin::API::Resources::DatasetExpansion',
     %w[created updated], 'storage', :account],
    ['DatasetExpansionHistory',
     'VpsAdmin::API::Resources::DatasetExpansion::History', %w[created],
     'storage', :account],
    ['Export', 'VpsAdmin::API::Resources::Export',
     %w[created updated deleted], 'storage', :account],
    ['ExportHost', 'VpsAdmin::API::Resources::Export::Host',
     %w[created updated deleted], 'storage', :account],
    ['SnapshotDownload', 'VpsAdmin::API::Resources::SnapshotDownload',
     %w[created deleted], 'storage', :account],
    ['Mount', 'VpsAdmin::API::Resources::VPS::Mount',
     %w[created updated deleted], 'storage', :account],

    # VPS
    ['Vps', 'VpsAdmin::API::Resources::VPS',
     %w[created updated deleted], 'vps', :account],
    ['VpsConsole', 'VpsAdmin::API::Resources::VPS::ConsoleToken',
     %w[created deleted], 'vps', :account],
    ['VpsFeature', 'VpsAdmin::API::Resources::VPS::Feature',
     %w[updated], 'vps', :account],
    ['VpsMaintenanceWindow',
     'VpsAdmin::API::Resources::VPS::MaintenanceWindow', %w[updated],
     'vps', :account],
    ['VpsUserData', 'VpsAdmin::API::Resources::VpsUserData',
     %w[created updated deleted], 'vps', :account],

    # Notification routing and preferences
    ['EventRoute', 'VpsAdmin::API::Resources::EventRoute',
     %w[created updated deleted], 'notifications', :account],
    ['EventRouteMatcher', 'VpsAdmin::API::Resources::EventRoute::Matcher',
     %w[created updated deleted], 'notifications', :account],
    ['EventRouteTimeInterval',
     'VpsAdmin::API::Resources::EventRoute::TimeInterval',
     %w[created updated deleted], 'notifications', :account],
    ['EventTimeInterval', 'VpsAdmin::API::Resources::EventTimeInterval',
     %w[created updated deleted], 'notifications', :account],
    ['NotificationReceiver',
     'VpsAdmin::API::Resources::NotificationReceiver',
     %w[created updated deleted], 'notifications', :account],
    ['NotificationReceiverTarget',
     'VpsAdmin::API::Resources::NotificationReceiver::Target',
     %w[created updated deleted], 'notifications', :account],
    ['NotificationTarget', 'VpsAdmin::API::Resources::NotificationTarget',
     %w[created updated deleted], 'notifications', :account],
    ['UserNotificationDeliveryMethod',
     'VpsAdmin::API::Resources::User::NotificationDeliveryMethod',
     %w[updated], 'notifications', :account],
    ['UserNotificationRateLimit',
     'VpsAdmin::API::Resources::User::NotificationRateLimit',
     %w[updated], 'notifications', :account],
    ['NotificationTemplate',
     'VpsAdmin::API::Resources::NotificationTemplate',
     %w[created updated deleted], 'notifications', :admin],
    ['NotificationTemplateVariant',
     'VpsAdmin::API::Resources::NotificationTemplate::Variant',
     %w[created updated deleted], 'notifications', :admin],
    # Authentication resources exposed to users or administrators
    ['MetricsAccessToken', 'VpsAdmin::API::Resources::MetricsAccessToken',
     %w[created deleted], 'security', :account],
    ['UserDevice', 'VpsAdmin::API::Resources::User::KnownDevice',
     %w[created deleted], 'security', :account],
    ['UserPublicKey', 'VpsAdmin::API::Resources::User::PublicKey',
     %w[created updated deleted], 'security', :account],
    ['UserSession', 'VpsAdmin::API::Resources::UserSession',
     %w[created updated], 'security', :account],
    ['UserTotpDevice', 'VpsAdmin::API::Resources::User::TotpDevice',
     %w[created updated deleted], 'security', :account],
    ['WebauthnCredential',
     'VpsAdmin::API::Resources::User::WebauthnCredential',
     %w[created updated deleted], 'security', :account],
    ['Oauth2Client', 'VpsAdmin::API::Resources::Oauth2Client',
     %w[created updated deleted], 'security', :admin],

    # Operating systems and global configuration
    ['OsFamily', 'VpsAdmin::API::Resources::OsFamily',
     %w[created updated deleted], 'operating_systems', :admin],
    ['OsTemplate', 'VpsAdmin::API::Resources::OsTemplate',
     %w[created updated deleted], 'operating_systems', :admin],
    ['SysConfig', 'VpsAdmin::API::Resources::SystemConfig',
     %w[updated], 'system', :admin],
    # Mail, incidents and monitoring
    ['Mailbox', 'VpsAdmin::API::Resources::Mailbox',
     %w[created updated deleted], 'mail', :admin],
    ['MailboxHandler', 'VpsAdmin::API::Resources::Mailbox::Handler',
     %w[created updated deleted], 'mail', :admin],
    ['IncidentReport', 'VpsAdmin::API::Resources::IncidentReport',
     %w[created], 'incidents', :account],
    ['SecurityAdvisory', 'VpsAdmin::API::Resources::SecurityAdvisory',
     %w[created updated], 'security', :admin],
    ['SecurityAdvisoryNodeStatus',
     'VpsAdmin::API::Resources::SecurityAdvisory::NodeStatus',
     %w[created updated deleted], 'security', :admin],
    ['SecurityAdvisoryCve',
     'VpsAdmin::API::Resources::SecurityAdvisoryCve',
     %w[created updated deleted], 'security', :admin],
    ['SecurityAdvisoryUpdate',
     'VpsAdmin::API::Resources::SecurityAdvisoryUpdate',
     %w[created updated deleted], 'security', :admin]
  ].to_h do |model_name, api_resources, actions, topic, audience|
    logical_name = RESOURCE_NAME_OVERRIDES.fetch(
      model_name,
      ActiveSupport::Inflector.underscore(model_name).tr('/', '_')
    )
    [
      model_name,
      CatalogEntry.new(
        model_name:,
        api_resources: Array(api_resources).freeze,
        actions: actions.freeze,
        topic:,
        audience:,
        logical_name:
      )
    ]
  end.freeze
  SENSITIVE_FIELDS_BY_MODEL = {
    'AuthToken' => %w[opts],
    'Event' => %w[parameters],
    'EventDelivery' => %w[
      payload
      response_headers
      target_secret
      target_value
    ],
    'EventDeliveryAttempt' => %w[response_body response_headers],
    'NotificationTarget' => %w[
      config
      identity_key
      secret
      target_value
      verification_token
    ],
    'NotificationTemplateVariant' => %w[html options text],
    'ObjectHistory' => %w[event_data],
    'OsTemplate' => %w[config],
    'SysConfig' => %w[value],
    'Transaction' => %w[input output],
    'TransactionConfirmation' => %w[attr_changes],
    'VpsUserData' => %w[content],
    'WebauthnChallenge' => %w[challenge]
  }.freeze
  SENSITIVE_FIELD_PATTERN = /
    (?:\A|_)
    (?:
      auth(?:entication)? |
      challenge |
      credential |
      encrypted |
      key |
      otp |
      pass(?:word|phrase|wd)? |
      private |
      recovery |
      secret |
      signature |
      token |
      verification
    )
    (?:\z|_)
  /ix
  ROUTING_FIELD_PATTERN = /
    \A(?:
      active |
      enabled |
      hostname |
      label |
      name |
      object_state |
      role |
      state |
      status |
      type |
      [a-z0-9_]+_(?:id|role|state|status|type)
    )\z
  /x
  INFER_RELATION = Object.new.freeze

  @owner_resolvers = {}
  @vps_resolvers = {}
  @registered_event_types = {}
  @resource_catalog = RESOURCE_CATALOG.dup

  module_function

  def emit!(
    action,
    object,
    owner: INFER_RELATION,
    vps: INFER_RELATION,
    changed_fields: [],
    changes: nil,
    occurred_at: nil
  )
    action = action.to_s
    raise ArgumentError, "unsupported resource event action #{action.inspect}" unless ACTIONS.include?(action)

    actor = ::User.current
    session = ::UserSession.current
    resource_name = resource_name_for(object)
    resource_id = resource_id_for(object)
    event_type = ensure_event_type!(object.class.base_class, action)
    vps = related_vps(object) if vps.equal?(INFER_RELATION)
    owner = resource_owner(object, vps:) if owner.equal?(INFER_RELATION)
    payload = payload_for(
      action,
      object,
      changed_fields:,
      changes:,
      actor:,
      session:
    )

    VpsAdmin::API::Events.emit!(
      event_type,
      user: owner,
      vps:,
      source_class: object.class.base_class.name,
      source_id: source_id_for(object),
      subject: "#{resource_name.humanize} ##{resource_id_label(resource_id)} #{action}",
      summary: resource_summary(
        action,
        resource_name,
        resource_id_label(resource_id),
        actor:
      ),
      payload:,
      ip_addr: session&.client_ip_addr || session&.api_ip_addr,
      occurred_at:
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

  def register_resource(
    model_name,
    api_resources:,
    actions:,
    topic:,
    audience:,
    logical_name: nil
  )
    model_name = model_name.to_s
    if @resource_catalog.has_key?(model_name)
      raise ArgumentError,
            "resource event model #{model_name} is already registered"
    end

    actions = Array(actions).map(&:to_s)
    invalid_actions = actions - ACTIONS
    unless invalid_actions.empty?
      raise ArgumentError,
            "#{model_name} has unsupported resource event actions: " \
            "#{invalid_actions.join(', ')}"
    end

    @resource_catalog[model_name] = CatalogEntry.new(
      model_name:,
      api_resources: Array(api_resources).map(&:to_s).freeze,
      actions: actions.freeze,
      topic: topic.to_s,
      audience: audience.to_sym,
      logical_name: logical_name || RESOURCE_NAME_OVERRIDES.fetch(
        model_name,
        ActiveSupport::Inflector.underscore(model_name).tr('/', '_')
      )
    )
  end

  def resource_catalog
    @resource_catalog.dup.freeze
  end

  def catalog_entry_for(object_or_class)
    klass =
      if object_or_class.is_a?(Class)
        object_or_class
      else
        object_or_class.class
      end

    @resource_catalog[klass.base_class.name]
  end

  def catalogued?(object_or_class, action = nil)
    entry = catalog_entry_for(object_or_class)
    return false unless entry
    return true if action.nil?

    entry.actions.include?(action.to_s)
  end

  def account_visible_event_type?(type)
    Array(type.roles).map(&:to_s).include?('account')
  end

  def category_label(category)
    category = category.to_s
    I18n.t(
      "vpsadmin.events.categories.#{category}",
      default: TOPIC_LABELS.fetch(category, category.humanize)
    )
  end

  def changed_fields_for(object)
    object.saved_changes.keys.map(&:to_s).reject do |field|
      IGNORED_CHANGED_FIELDS.include?(field)
    end
  end

  def resource_name_for(object_or_class)
    klass =
      if object_or_class.is_a?(Class)
        object_or_class
      else
        object_or_class.class
      end
    model_name = klass.base_class.name

    entry = @resource_catalog[model_name]
    return entry.logical_name if entry

    RESOURCE_NAME_OVERRIDES.fetch(
      model_name,
      ActiveSupport::Inflector.underscore(model_name).tr('/', '_')
    )
  end

  def event_name(action, object_or_class)
    "#{resource_name_for(object_or_class)}.#{action}"
  end

  def resource_id_for(object)
    fields = Array(object.class.base_class.primary_key).map(&:to_s)
    return object.id if fields.length <= 1

    fields.to_h { |field| [field, normalize_value(object[field])] }
  end

  def source_id_for(object)
    resource_id = resource_id_for(object)
    resource_id if resource_id.is_a?(Integer)
  end

  def resource_id_label(resource_id)
    return resource_id unless resource_id.is_a?(Hash)

    resource_id.map { |field, value| "#{field}=#{value}" }.join(',')
  end

  def resource_event?(event_or_name)
    type =
      if event_or_name.respond_to?(:event_type)
        VpsAdmin::API::Events.type_for(event_or_name.event_type)
      else
        VpsAdmin::API::Events.type_for(event_or_name.to_s)
      end

    type&.resource.present?
  end

  def payload_for(action, object, changed_fields: [], changes: nil, actor: ::User.current,
                  session: ::UserSession.current)
    action = action.to_s
    model = object.class.base_class
    resource_name = resource_name_for(model)
    raw_changes = raw_changes_for(
      action,
      object,
      changed_fields:,
      changes:
    )
    encoded_changes = raw_changes.to_h do |field, change|
      encoded = {}
      if change.fetch(:old_present)
        encoded['old'] = value_envelope(model, field, change[:old])
      end
      if change.fetch(:new_present)
        encoded['new'] = value_envelope(model, field, change[:new])
      end
      [field, encoded]
    end

    {
      resource_schema_version: SCHEMA_VERSION,
      resource_name:,
      resource_action: action,
      resource_id: resource_id_for(object),
      actor_user_id: actor&.id,
      actor_user_login: actor&.login,
      admin_user_id: session&.admin_id,
      user_session_id: session&.id,
      changed_fields: encoded_changes.keys.sort,
      changes: encoded_changes.sort.to_h
    }.compact.tap { |payload| enforce_payload_budget!(payload) }
  end

  def raw_changes_for(action, object, changed_fields:, changes:)
    action = action.to_s
    fields =
      if %w[created deleted].include?(action)
        auditable_attribute_names(object.class.base_class)
      else
        Array(changed_fields).map(&:to_s)
      end
    fields |= changes.keys.map(&:to_s) if changes
    fields -= IGNORED_CHANGED_FIELDS

    fields.sort.each_with_object({}) do |field, ret|
      next unless object.has_attribute?(field)

      explicit = changes && (changes[field] || changes[field.to_sym])
      if explicit
        old_value, new_value, old_present, new_present = explicit_change(explicit)
      else
        saved =
          object.changes_to_save[field] ||
          object.saved_changes[field] ||
          object.previous_changes[field]
        case action
        when 'created'
          old_value = nil
          new_value = object[field]
          old_present = false
          new_present = true
        when 'deleted'
          old_value = object[field]
          new_value = nil
          old_present = true
          new_present = false
        else
          old_value, new_value = saved || [nil, object[field]]
          old_present = !saved.nil?
          new_present = true
        end
      end
      old_present = false if action == 'created'
      new_present = false if action == 'deleted'

      next if old_present && new_present && old_value == new_value

      ret[field] = {
        old: old_value,
        new: new_value,
        old_present:,
        new_present:
      }
    end
  end

  def explicit_change(change)
    if change.is_a?(Hash)
      old_present = change.has_key?(:old) || change.has_key?('old')
      new_present = change.has_key?(:new) || change.has_key?('new')
      return [
        change.has_key?(:old) ? change[:old] : change['old'],
        change.has_key?(:new) ? change[:new] : change['new'],
        old_present,
        new_present
      ]
    end

    old_value, new_value = Array(change)
    [old_value, new_value, true, true]
  end

  def value_envelope(model, field, value)
    return { 'kind' => 'redacted' } if sensitive_field?(model, field)

    normalized = normalize_value(value)
    json = JSON.generate(normalized)
    return digest_envelope(json) if json.bytesize > MAX_INLINE_VALUE_BYTES

    { 'kind' => 'value', 'value' => normalized }
  rescue JSON::GeneratorError, TypeError
    json = JSON.generate(value.to_s)
    if json.bytesize > MAX_INLINE_VALUE_BYTES
      digest_envelope(json)
    else
      { 'kind' => 'value', 'value' => value.to_s }
    end
  end

  def normalize_value(value)
    case value
    when ActiveSupport::TimeWithZone, DateTime, Time, Date
      value.iso8601
    when BigDecimal
      value.to_s('F')
    when Symbol
      value.to_s
    when Hash
      value.to_h.sort_by { |key, _| key.to_s }.to_h do |key, item|
        [key.to_s, normalize_value(item)]
      end
    when Array
      value.map { |item| normalize_value(item) }
    when String, Integer, Float, TrueClass, FalseClass, NilClass
      value
    else
      value.respond_to?(:as_json) ? normalize_value(value.as_json) : value.to_s
    end
  end

  def digest_envelope(json)
    {
      'kind' => 'digest',
      'algorithm' => 'sha256',
      'digest' => Digest::SHA256.hexdigest(json),
      'bytes' => json.bytesize
    }
  end

  def enforce_payload_budget!(payload)
    while JSON.generate(payload).bytesize > MAX_PAYLOAD_BYTES
      candidates = payload.fetch(:changes).flat_map do |field, change|
        change.filter_map do |side, envelope|
          next unless envelope['kind'] == 'value'

          json = JSON.generate(envelope['value'])
          [json.bytesize, field, side, json]
        end
      end
      break if candidates.empty?

      _, field, side, json = candidates.max_by(&:first)
      payload.fetch(:changes).fetch(field)[side] = digest_envelope(json)
    end

    payload
  end

  def sensitive_field?(model, field)
    model_name = model.is_a?(Class) ? model.base_class.name : model.to_s

    SENSITIVE_FIELD_PATTERN.match?(field.to_s) ||
      SENSITIVE_FIELDS_BY_MODEL.fetch(model_name, []).include?(field.to_s)
  end

  def auditable_attribute_names(model)
    model.attribute_names.map(&:to_s) - IGNORED_CHANGED_FIELDS
  end

  def refresh_event_types!
    @resource_catalog.each_value do |entry|
      resource_classes = entry.api_resources.map(&:constantize)
      model = entry.model_name.constantize

      validate_catalog_entry!(entry, model, resource_classes)
      next unless model.table_exists?

      entry.actions.each { |action| ensure_event_type!(model, action) }
    rescue ActiveRecord::ActiveRecordError
      next
    end
  end

  def ensure_event_type!(model, action)
    model = model.base_class
    action = action.to_s
    entry = @resource_catalog[model.name]
    unless entry
      raise ArgumentError,
            "#{model.name} is not an outside-visible resource event model"
    end
    unless entry.actions.include?(action)
      raise ArgumentError,
            "#{model.name} does not publish a #{action} resource event"
    end

    event_type = event_name(action, model)
    cache_key = [event_type, model.name]
    return event_type if @registered_event_types[cache_key]

    descriptor = resource_descriptor(model, action)
    type = VpsAdmin::API::Events.type_for(event_type)
    if type && type.resource.nil?
      raise ArgumentError,
            "#{event_type} is reserved for a typed resource event, " \
            'but a semantic event already uses that name'
    end

    generated = type.nil?
    unless type
      matcher_fields = resource_matcher_fields(model, action)
      resource_name = resource_name_for(model)
      attribute_names = auditable_attribute_names(model)
      examples = resource_examples(model, resource_name, action)
      roles = entry.audience == :account ? %i[account admin] : %i[admin]
      VpsAdmin::API::Events.define do
        event event_type,
              label: "#{resource_name.humanize} #{action}",
              category: entry.topic,
              severity: :info,
              roles:,
              default_routed: false,
              examples: examples do
          fields VpsAdmin::API::Events::Core::OPERATION_RESULT_FIELDS
          field(
            :changed_fields,
            'Logical resource attributes changed by the operation',
            type: :string_list,
            choices: attribute_names,
            example: attribute_names.first(2)
          )
          fields matcher_fields
        end
      end
      type = VpsAdmin::API::Events.type_for(event_type)
    end

    merge_resource_matcher_fields!(type, model, action)
    VpsAdmin::API::Events.attach_resource_descriptor(
      event_type,
      descriptor,
      generated:
    )
    @registered_event_types[cache_key] = true
    event_type
  end

  def validate_catalog_entry!(entry, model, resource_classes)
    unless TOPICS.include?(entry.topic)
      raise ArgumentError,
            "#{entry.model_name} has unsupported event topic #{entry.topic.inspect}"
    end
    unless AUDIENCES.include?(entry.audience)
      raise ArgumentError,
            "#{entry.model_name} has unsupported event audience " \
            "#{entry.audience.inspect}"
    end
    if entry.audience == :account && !@owner_resolvers.has_key?(entry.model_name)
      raise ArgumentError,
            "#{entry.model_name} is account-visible but has no owner resolver"
    end

    resource_classes.each do |resource_class|
      unless resource_class < HaveAPI::Resource
        raise ArgumentError,
              "#{resource_class.name} is not a HaveAPI resource"
      end
      resource_model = resource_class.model
      unless resource_model&.base_class == model
        raise ArgumentError,
              "#{resource_class.name} does not expose #{entry.model_name}"
      end
    end

    default_actions = resource_classes.flat_map do |resource_class|
      resource_class.actions.filter_map do |action_class|
        if action_class <= HaveAPI::Actions::Default::Create
          'created'
        elsif action_class <= HaveAPI::Actions::Default::Update
          'updated'
        elsif action_class <= HaveAPI::Actions::Default::Delete
          'deleted'
        end
      end
    end.uniq
    missing_actions = default_actions - entry.actions
    return if missing_actions.empty?

    raise ArgumentError,
          "#{entry.model_name} catalog is missing resource actions: " \
          "#{missing_actions.join(', ')}"
  end

  def resource_descriptor(model, action)
    id = resource_id_descriptor(model)
    {
      name: resource_name_for(model),
      action: action.to_s,
      schema_version: SCHEMA_VERSION,
      id_type: id.fetch(:type),
      id_attributes: id[:attributes],
      attributes: auditable_attribute_names(model).filter_map do |name|
        column = model.columns_hash[name]
        next unless column

        matcher = routing_attribute?(model, name)
        choices = enum_choices(model, name)
        {
          name:,
          type: logical_attribute_type(model, name, column, choices:),
          nullable: column.null,
          choices:,
          value_policy: sensitive_field?(model, name) ? 'redacted' : 'value_or_digest',
          old_matcher: matcher && action.to_s != 'created',
          new_matcher: matcher && action.to_s != 'deleted'
        }.compact
      end
    }
  end

  def resource_matcher_fields(model, action)
    auditable_attribute_names(model).each_with_object({}) do |name, ret|
      next unless routing_attribute?(model, name)

      choices = enum_choices(model, name)
      config = {
        description: "Previous value of #{name}",
        type: logical_routing_attribute_type(model, name, choices:),
        choices:
      }.compact
      ret[:"old_#{name}"] = config if action.to_s != 'created'
      next if action.to_s == 'deleted'

      ret[:"new_#{name}"] = config.merge(
        description: "New value of #{name}"
      )
    end
  end

  def merge_resource_matcher_fields!(type, model, action)
    existing = type.fields.to_h { |field| [field.fetch(:name), field] }
    resource_matcher_fields(model, action).each do |name, config|
      next if existing.has_key?(name.to_s)

      type.fields << VpsAdmin::API::Events::FieldDefinition.new(
        name:,
        description: config.fetch(:description),
        type: config.fetch(:type),
        example: config[:example],
        choices: config[:choices],
        block: nil
      ).to_h.merge(resource_attribute: true)
    end
  end

  def routing_attribute?(model, name)
    return false if sensitive_field?(model, name)
    return false unless ROUTING_FIELD_PATTERN.match?(name)

    !logical_routing_attribute_type(model, name).nil?
  end

  def logical_routing_attribute_type(model, name, choices: enum_choices(model, name))
    return :string if choices
    return if serialized_attribute?(model, name)

    routing_attribute_type(model.columns_hash.fetch(name))
  end

  def routing_attribute_type(column)
    case column.type
    when :integer, :bigint
      :integer
    when :decimal, :float
      :number
    when :boolean
      :boolean
    when :date, :datetime, :timestamp, :time
      :datetime
    when :string, :text
      :string
    end
  end

  def logical_attribute_type(model, name, column, choices: enum_choices(model, name))
    return 'string' if choices
    return 'json' if serialized_attribute?(model, name)
    return 'string' if column.type == :decimal

    attribute_type(column)
  end

  def attribute_type(column)
    return 'string' unless column

    case column.type
    when :integer, :bigint
      'integer'
    when :float
      'number'
    when :boolean
      'boolean'
    when :date, :datetime, :timestamp, :time
      'datetime'
    when :json
      'json'
    else
      'string'
    end
  end

  def serialized_attribute?(model, name)
    model.type_for_attribute(name).serialized?
  end

  def enum_choices(model, name)
    model.defined_enums[name]&.keys
  end

  def resource_id_descriptor(model)
    fields = Array(model.primary_key).map(&:to_s)
    return { type: 'string' } if fields.empty?

    if fields.length == 1
      return {
        type: attribute_type(model.columns_hash[fields.first])
      }
    end

    {
      type: 'object',
      attributes: fields.map do |field|
        {
          name: field,
          type: logical_attribute_type(
            model,
            field,
            model.columns_hash.fetch(field)
          )
        }
      end
    }
  end

  def resource_examples(model, resource_name, action)
    label = resource_id_label(resource_id_example(model))
    {
      subject: "#{resource_name.humanize} ##{label} #{action}",
      summary: "alice (user #123) #{action} #{resource_name.humanize} ##{label}"
    }
  end

  def resource_id_example(model)
    descriptor = resource_id_descriptor(model)
    return 42 if descriptor.fetch(:type) == 'integer'
    return 'example-id' unless descriptor.fetch(:type) == 'object'

    descriptor.fetch(:attributes).to_h do |attribute|
      example =
        case attribute.fetch(:type)
        when 'integer'
          42
        when 'number'
          3.14
        else
          'example'
        end
      [attribute.fetch(:name), example]
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

  def resource_summary(action, resource_name, resource_id, actor:)
    actor_label =
      if actor
        "#{actor.login} (user ##{actor.id})"
      else
        'System'
      end

    "#{actor_label} #{action} #{resource_name.humanize} ##{resource_id}"
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
  'UserClusterResource',
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
  'DatasetInPoolPlan',
  via: %i[dataset_in_pool dataset user]
)

VpsAdmin::API::Events::ResourceOperations.register_owner(
  'DatasetExpansionHistory',
  via: %i[dataset_expansion dataset user]
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

require_relative 'action_policies'
