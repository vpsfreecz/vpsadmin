module VpsAdmin::API::Events::ActionPolicies
  @external = {}
  @declared_policy_classes = []
  @external_policy_execution = {}

  module_function

  def declare_policy(
    owner,
    kind:,
    models: [],
    reason: nil,
    atomic: true,
    emit_on_failure: false
  )
    if owner.instance_variable_defined?(:@event_policy)
      raise ArgumentError, "event policy is already declared for #{owner.name}"
    end

    policy = build_policy(
      owner.name,
      kind:,
      models:,
      reason:,
      atomic:,
      emit_on_failure:,
      resolve_models: true
    )
    owner.instance_variable_set(:@event_policy, policy)
    @declared_policy_classes << owner
    policy
  end

  def register_external(
    name,
    kind:,
    models: [],
    reason: nil,
    atomic: false,
    emit_on_failure: false
  )
    name = name.to_s
    policy = build_policy(
      "external event policy #{name.inspect}",
      kind:,
      models:,
      reason:,
      atomic:,
      emit_on_failure:,
      resolve_models: false
    )
    existing = @external[name]
    return existing if existing == policy

    if existing
      raise ArgumentError,
            "external event policy #{name.inspect} conflicts with its existing declaration"
    end

    @external[name] = policy
  end

  def build_policy(
    owner_name,
    kind:,
    models:,
    reason:,
    atomic:,
    emit_on_failure:,
    resolve_models:
  )
    normalized_models =
      if models == :all
        :all
      else
        Array(models).map do |model|
          unless resolve_models
            next model.is_a?(Class) ? model.base_class.name : model.to_s
          end

          klass = model.is_a?(Class) ? model : model.to_s.constantize
          validate_application_model!(klass)
          klass.base_class.name
        end.uniq.freeze
      end
    policy = Policy.new(
      kind:,
      models: normalized_models,
      reason:,
      atomic:,
      emit_on_failure:
    )
    if policy.kind != :resource && reason.blank?
      raise ArgumentError,
            "#{owner_name} event policy #{policy.kind.inspect} requires a reason"
    end

    policy
  end
  private_class_method :build_policy

  def validate_application_model!(model)
    return if model < ::ApplicationRecord

    raise ArgumentError, "#{model} is not an application model"
  end
  private_class_method :validate_application_model!

  def validate_external_models!
    @external.each_value do |policy|
      next unless RESOURCE_POLICY_KINDS.include?(policy.kind)
      next if policy.models == :all

      policy.models.each do |model_name|
        validate_application_model!(model_name.constantize)
      end
    end
  end
  private_class_method :validate_external_models!

  def delete_cascades
    ::ApplicationRecord.descendants.to_h do |model|
      [model.base_class.name, model.event_delete_cascade_associations]
    end.reject { |_model_name, associations| associations.empty? }.freeze
  end

  def for(action)
    explicit = action.event_policy
    return explicit if explicit

    method = action.http_method.to_sym
    unless MUTATING_HTTP_METHODS.include?(method)
      return Policy.new(kind: :read, models: [], reason: nil, atomic: false)
    end

    if action.blocking
      model_name = action.model&.base_class&.name
      return Policy.new(
        kind: :transaction_chain,
        models: model_name ? [model_name] : [],
        reason: 'covered by transaction-chain operation lifecycle events',
        atomic: false,
        resource_action: default_resource_action(action)
      )
    end

    action_name = default_resource_action(action)
    return unless action_name

    model_name = action.model&.base_class&.name
    return unless model_name

    Policy.new(kind: :resource, models: [model_name], reason: nil, atomic: true)
  end

  def mutating?(action)
    MUTATING_HTTP_METHODS.include?(action.http_method.to_sym)
  end

  def finalize!
    missing = mounted_actions.select do |action|
      mutating?(action) && self.for(action).nil?
    end
    return if missing.empty?

    names = missing.map(&:name).sort.join("\n")
    raise ArgumentError,
          "mounted mutating actions are missing event policies:\n#{names}"
  end

  def for_operation(operation)
    operation.event_policy
  end

  def operation_policies
    @declared_policy_classes.filter_map do |owner|
      next unless owner <= VpsAdmin::API::Operations::Base

      [owner.name, owner.event_policy]
    end.to_h.freeze
  end

  def external_policy(name)
    @external.fetch(name.to_s)
  end

  def external_policies
    @external.dup.freeze
  end

  def external_policy_execution(owner)
    @external_policy_execution.fetch(owner)
  end

  def current_recorder
    Thread.current[:vpsadmin_api_event_action_recorder]
  end

  def with_recorder(recorder)
    previous = current_recorder
    Thread.current[:vpsadmin_api_event_action_recorder] = recorder
    yield
  ensure
    Thread.current[:vpsadmin_api_event_action_recorder] = previous
  end

  def prepare_update(object)
    current_recorder&.prepare_update(object)
  end

  def record(action, object, changed_fields: nil, before_values: nil)
    current_recorder&.record(
      action,
      object,
      changed_fields:,
      before_values:
    )
  end

  def record_many(action, objects, changed_fields: nil)
    objects.each { |object| record(action, object, changed_fields:) }
  end

  def record_delete_cascades(object)
    recorder = current_recorder
    return unless recorder

    objects = collect_delete_cascades(object, {})
    recorder.allow_models(objects.map { |record| record.class.base_class.name })
    record_many(:deleted, objects)
  end

  def defer_transaction_chain_resources!(chain)
    recorder = current_recorder
    return unless recorder&.transaction_chain?

    recorder.defer_to!(chain)
    ActiveRecord.after_all_transactions_commit { recorder.consume! }
  end

  def collect_delete_cascades(object, visited)
    key = [object.class.base_class.name, object.id]
    return [] if visited[key]

    visited[key] = true
    associations = object.class.base_class.event_delete_cascade_associations
    return [] if associations.empty?

    associations.flat_map do |association|
      value = object.public_send(association)
      children = value.respond_to?(:to_ary) ? value.to_ary : Array(value)
      children.compact.flat_map do |child|
        child_key = [child.class.base_class.name, child.id]
        next [] if visited[child_key]

        [child, *collect_delete_cascades(child, visited)]
      end
    end
  end
  private_class_method :collect_delete_cascades

  def capture(policy, &block)
    return block.call unless policy.records_resources?

    if current_recorder
      current_recorder.allow_models(policy.models)
      return block.call
    end

    recorder = Recorder.new(policy)
    result = nil

    if policy.atomic
      ::ApplicationRecord.transaction(requires_new: true) do
        result = with_recorder(recorder, &block)
        recorder.emit!
      end
    else
      result = with_recorder(recorder, &block)
      recorder.emit!
    end

    result
  end

  def install!
    return if @installed

    validate_external_models!
    ::ApplicationRecord.after_create do
      VpsAdmin::API::Events::ActionPolicies.record(:created, self)
    end
    ::ApplicationRecord.before_update(prepend: true) do
      VpsAdmin::API::Events::ActionPolicies.prepare_update(self)
    end
    ::ApplicationRecord.after_update do
      VpsAdmin::API::Events::ActionPolicies.record(:updated, self)
    end
    ::ApplicationRecord.before_destroy(prepend: true) do
      VpsAdmin::API::Events::ActionPolicies.record_delete_cascades(self)
      VpsAdmin::API::Events::ActionPolicies.record(:deleted, self)
    end

    HaveAPI::Action.prepend(ActionExecution)
    VpsAdmin::API::Operations::Base.singleton_class.prepend(OperationExecution)
    oauth2_config = VpsAdmin::API::Authentication::OAuth2Config
    oauth2_execution = ExternalPolicyExecution.build(oauth2_config)
    oauth2_config.prepend(oauth2_execution)
    @external_policy_execution[oauth2_config] = oauth2_execution
    VpsAdmin::API::Notifications.singleton_class.prepend(
      NotificationCallbackExecution
    )
    @installed = true
  end

  def default_resource_action(action)
    if action <= HaveAPI::Actions::Default::Create
      :created
    elsif action <= HaveAPI::Actions::Default::Update
      :updated
    elsif action <= HaveAPI::Actions::Default::Delete
      :deleted
    end
  end
  private_class_method :default_resource_action

  def mounted_actions
    walk = lambda do |resource|
      actions = []
      resource.actions { |action| actions << action }
      resource.resources { |child| actions.concat(walk.call(child)) }
      actions
    end

    HaveAPI.get_version_resources(
      VpsAdmin::API::Resources,
      HaveAPI.implicit_version
    ).flat_map { |resource| walk.call(resource) }
  end
  private_class_method :mounted_actions
end
