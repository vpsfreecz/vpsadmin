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
  Declaration = Data.define(
    :resource_class,
    :topic,
    :audience,
    :logical_name,
    :owner,
    :vps,
    :redact,
    :additional_actions
  )
  CatalogEntry = Data.define(
    :model,
    :model_name,
    :api_resources,
    :actions,
    :topic,
    :audience,
    :logical_name,
    :owner,
    :vps,
    :redact
  )
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

  @declarations = []
  @registered_event_types = {}
  @resource_catalog = {}
  @catalog_mutex = Mutex.new
  @catalog_finalized = false

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

    catalog_entry_for(object)&.owner&.call(object)
  end

  def related_vps(object)
    catalog_entry_for(object)&.vps&.call(object)
  end

  def declare_resource(
    resource_class,
    topic:,
    audience:,
    name: nil,
    owner: nil,
    vps: nil,
    redact: [],
    additional_actions: []
  )
    unless resource_class < HaveAPI::Resource
      raise ArgumentError, "#{resource_class} is not a HaveAPI resource"
    end

    additional_actions = Array(additional_actions).map(&:to_s)
    invalid_actions = additional_actions - ACTIONS
    unless invalid_actions.empty?
      raise ArgumentError,
            "#{resource_class.name} has unsupported resource event actions: " \
            "#{invalid_actions.join(', ')}"
    end

    declaration = Declaration.new(
      resource_class:,
      topic: topic.to_s,
      audience: audience.to_sym,
      logical_name: name&.to_s,
      owner:,
      vps:,
      redact: Array(redact).map(&:to_s).uniq.sort.freeze,
      additional_actions: additional_actions.uniq.freeze
    )
    @catalog_mutex.synchronize do
      previous = @declarations.find do |item|
        item.resource_class.name == resource_class.name
      end
      if previous
        if previous.resource_class.equal?(resource_class)
          raise ArgumentError,
                "resource events are already declared for #{resource_class.name}"
        end
        unless declaration_metadata(declaration) == declaration_metadata(previous)
          raise ArgumentError,
                "conflicting resource event reload for #{resource_class.name}"
        end

        @declarations.delete(previous)
      end
      @declarations << declaration
      @catalog_finalized = false
    end
  end

  def resource_catalog
    ensure_catalog_finalized!
    @resource_catalog.dup.freeze
  end

  def catalog_entry_for(object_or_class)
    klass =
      if object_or_class.is_a?(Class)
        object_or_class
      else
        object_or_class.class
      end

    ensure_catalog_finalized!
    @resource_catalog[klass.base_class.name]
  end

  def catalogued?(object_or_class, action = nil)
    entry = catalog_entry_for(object_or_class)
    return false unless entry
    return true if action.nil?

    entry.actions.include?(action.to_s)
  end

  def account_visible_event_type?(type)
    type.audience.to_sym == :account
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

    ensure_catalog_finalized!
    entry = @resource_catalog[model_name]
    return entry.logical_name if entry

    ActiveSupport::Inflector.underscore(model_name).tr('/', '_')
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
    model = model.is_a?(Class) ? model.base_class : model.to_s.constantize
    ensure_catalog_finalized!
    declaration_fields = @resource_catalog[model.name]&.redact || []

    SENSITIVE_FIELD_PATTERN.match?(field.to_s) ||
      model.event_redacted_fields.include?(field.to_s) ||
      declaration_fields.include?(field.to_s)
  end

  def auditable_attribute_names(model)
    model.attribute_names.map(&:to_s) - IGNORED_CHANGED_FIELDS
  end

  def refresh_event_types!
    finalize_catalog!
    validate_mounted_resources!

    @resource_catalog.each_value do |entry|
      model = entry.model

      next unless model.table_exists?

      entry.actions.each { |action| ensure_event_type!(model, action) }
    rescue ActiveRecord::ActiveRecordError
      next
    end
  end

  def ensure_event_type!(model, action)
    model = model.base_class
    action = action.to_s
    ensure_catalog_finalized!
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
              audience: entry.audience,
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
    if entry.audience == :account && entry.owner.nil?
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

  def resolver_for(specification)
    case specification
    when nil
      nil
    when :self
      ->(object) { object }
    when Proc
      specification
    else
      association_resolver(specification)
    end
  end
  private_class_method :resolver_for

  def declaration_metadata(declaration)
    declaration.to_h.except(:resource_class)
  end
  private_class_method :declaration_metadata

  def finalize_catalog!
    @catalog_mutex.synchronize do
      finalize_catalog_without_lock!
    end
  end
  private_class_method :finalize_catalog!

  def ensure_catalog_finalized!
    return if @catalog_finalized

    @catalog_mutex.synchronize do
      finalize_catalog_without_lock! unless @catalog_finalized
    end
  end
  private_class_method :ensure_catalog_finalized!

  def finalize_catalog_without_lock!
    validate_model_redactions!
    catalog = {}

    @declarations.group_by do |declaration|
      declaration.resource_class.model&.base_class&.name
    end.each do |model_name, declarations|
      unless model_name
        names = declarations.map { |item| item.resource_class.name }.join(', ')
        raise ArgumentError, "resource event declarations have no model: #{names}"
      end

      reference = declarations.first
      logical_name = reference.logical_name ||
                     ActiveSupport::Inflector.underscore(model_name).tr('/', '_')
      declarations.drop(1).each do |declaration|
        next if declarations_compatible?(reference, declaration, logical_name:)

        raise ArgumentError,
              "conflicting resource event declarations for #{model_name}: " \
              "#{reference.resource_class.name} and " \
              "#{declaration.resource_class.name}"
      end

      resource_classes = declarations.map(&:resource_class)
      model = reference.resource_class.model.base_class
      redacted_fields = declarations.flat_map(&:redact).uniq.sort.freeze
      validate_redaction_fields!(
        model,
        redacted_fields,
        "resource_events for #{resource_classes.map(&:name).join(', ')}"
      )
      actions = (
        default_actions_for(resource_classes) +
        declarations.flat_map(&:additional_actions)
      ).uniq.sort
      entry = CatalogEntry.new(
        model:,
        model_name:,
        api_resources: resource_classes.uniq.freeze,
        actions: actions.freeze,
        topic: reference.topic,
        audience: reference.audience,
        logical_name:,
        owner: resolver_for(reference.owner),
        vps: resolver_for(reference.vps),
        redact: redacted_fields
      )
      validate_catalog_entry!(entry, model, resource_classes)
      catalog[model_name] = entry
    end

    duplicate_names = catalog.values.group_by(&:logical_name).select do |_name, entries|
      entries.length > 1
    end
    unless duplicate_names.empty?
      details = duplicate_names.map do |name, entries|
        "#{name} (#{entries.map(&:model_name).join(', ')})"
      end
      raise ArgumentError,
            "duplicate logical resource event names: #{details.join('; ')}"
    end

    @resource_catalog = catalog.freeze
    @catalog_finalized = true
  end
  private_class_method :finalize_catalog_without_lock!

  def validate_model_redactions!
    ::ApplicationRecord.descendants.each do |model|
      fields = model.event_redacted_fields
      next if fields.empty?

      validate_redaction_fields!(model, fields, "#{model.name}.event_redact")
    end
  end
  private_class_method :validate_model_redactions!

  def validate_redaction_fields!(model, fields, declaration)
    unknown_fields = fields - auditable_attribute_names(model)
    return if unknown_fields.empty?

    raise ArgumentError,
          "#{declaration} contains non-auditable model attributes: " \
          "#{unknown_fields.join(', ')}"
  end
  private_class_method :validate_redaction_fields!

  def declarations_compatible?(left, right, logical_name:)
    right_logical_name = right.logical_name ||
                         ActiveSupport::Inflector.underscore(
                           right.resource_class.model.base_class.name
                         ).tr('/', '_')
    left.topic == right.topic &&
      left.audience == right.audience &&
      logical_name == right_logical_name &&
      left.owner == right.owner &&
      left.vps == right.vps
  end
  private_class_method :declarations_compatible?

  def default_actions_for(resource_classes)
    resource_classes.flat_map do |resource_class|
      resource_class.actions.filter_map do |action_class|
        if action_class <= HaveAPI::Actions::Default::Create
          'created'
        elsif action_class <= HaveAPI::Actions::Default::Update
          'updated'
        elsif action_class <= HaveAPI::Actions::Default::Delete
          'deleted'
        end
      end
    end
  end
  private_class_method :default_actions_for

  def validate_mounted_resources!
    missing = mounted_resource_classes.filter_map do |resource_class|
      model = resource_class.model
      next unless model

      actions = default_actions_for([resource_class])
      next if actions.empty?

      entry = @resource_catalog[model.base_class.name]
      missing_actions = entry ? actions - entry.actions : actions
      next if missing_actions.empty?

      "#{resource_class.name}: #{missing_actions.sort.join(', ')}"
    end
    return if missing.empty?

    raise ArgumentError,
          'mounted resources are missing resource event declarations: ' \
          "#{missing.sort.join('; ')}"
  end
  private_class_method :validate_mounted_resources!

  def mounted_resource_classes
    walk = lambda do |resource_class|
      resources = [resource_class]
      resource_class.resources do |child|
        resources.concat(walk.call(child))
      end
      resources
    end

    HaveAPI.get_version_resources(
      VpsAdmin::API::Resources,
      HaveAPI.implicit_version
    ).flat_map { |resource_class| walk.call(resource_class) }
  end
  private_class_method :mounted_resource_classes

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

module VpsAdmin::API::Events::ResourceDeclaration
  def resource_events(**)
    VpsAdmin::API::Events::ResourceOperations.declare_resource(self, **)
  end
end

HaveAPI::Resource.extend(VpsAdmin::API::Events::ResourceDeclaration)

require_relative 'action_policies'
