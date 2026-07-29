module VpsAdmin::API::Events::ActionPolicies
  MUTATING_HTTP_METHODS = %i[delete patch post put].freeze

  Policy = Data.define(
    :kind,
    :models,
    :reason,
    :atomic,
    :emit_on_failure,
    :resource_action
  ) do
    def initialize(
      kind:,
      models:,
      reason:,
      atomic:,
      emit_on_failure: false,
      resource_action: nil
    )
      super
    end

    def records_resources?
      kind == :resource
    end

    def records_transaction_chain_resources?
      kind == :transaction_chain && (models == :all || models.any?)
    end
  end

  class Recorder
    UNKNOWN_VALUE = Object.new.freeze
    NONEXISTENT_VALUE = Object.new.freeze
    CONFIRM_ACTIONS = {
      'create_type' => :created,
      'just_create_type' => :created,
      'edit_before_type' => :updated,
      'edit_after_type' => :updated,
      'destroy_type' => :deleted,
      'just_destroy_type' => :deleted,
      'decrement_type' => :updated,
      'increment_type' => :updated
    }.freeze

    FieldState = Data.define(:before_value, :observed_values)
    Entry = Data.define(
      :initially_persisted,
      :initial_values,
      :object,
      :owner,
      :vps,
      :field_states
    )
    Fact = Data.define(:action, :object, :owner, :vps, :changed_fields, :changes)

    def initialize(policy)
      @model_names = policy.models
      @resource_action = policy.resource_action&.to_sym
      @resource_action_model_names =
        policy.models == :all ? :all : policy.models.dup.freeze
      @transaction_chain = policy.records_transaction_chain_resources?
      @entries = {}
      @already_emitted = {}
      @pending_updates = {}
    end

    def prepare_update(object)
      return unless records_model?(object, :updated)

      fields = object.changes_to_save.keys.map(&:to_s).reject do |field|
        VpsAdmin::API::Events::ResourceOperations::IGNORED_CHANGED_FIELDS.include?(field)
      end
      return if fields.empty?

      row = persisted_row(object, fields)
      return unless row

      @pending_updates[pending_update_key(object)] =
        fields.to_h { |field| [field, snapshot_value(row[field])] }
    end

    def record(action, object, changed_fields: nil, before_values: nil)
      if object.is_a?(::Event)
        record_existing_event(object)
        return
      end

      return unless records_model?(object, action)

      key = resource_key(object)
      old = @entries[key]
      operations = VpsAdmin::API::Events::ResourceOperations
      vps = operations.related_vps(object)
      owner = operations.resource_owner(object, vps:)
      changed_fields =
        if action == :deleted
          []
        elsif changed_fields
          Array(changed_fields).map(&:to_s)
        else
          VpsAdmin::API::Events::ResourceOperations.changed_fields_for(object)
        end
      pending_before_values =
        if action == :updated
          @pending_updates.delete(pending_update_key(object))
        end
      observed_fields = observed_fields_for(
        action,
        object,
        changed_fields,
        before_values || pending_before_values
      )

      merged = merge(
        old,
        action,
        object,
        owner,
        vps,
        observed_fields
      )
      @entries[key] = merged
    end

    def allow_models(models)
      @model_names =
        if @model_names == :all || models == :all
          :all
        else
          (@model_names + Array(models).map(&:to_s)).uniq.freeze
        end
    end

    def emit!
      without_capture do
        @entries.each_value do |entry|
          resolved = resolve(entry)
          next unless resolved

          action, changed_fields, changes = resolved
          action = resource_action_for(entry.object, action)
          changed_fields = [] if action == :deleted

          key = resource_event_key(entry.object, action)
          next if already_emitted?(key)

          VpsAdmin::API::Events::ResourceOperations.emit!(
            action,
            entry.object,
            owner: entry.owner,
            vps: entry.vps,
            changed_fields:,
            changes:
          )
        end
      end
    end

    def transaction_chain?
      @transaction_chain
    end

    def pending?
      @entries.any?
    end

    def defer_to!(chain)
      facts = resolved_facts
      merge_confirmation_facts!(facts, chain)

      without_capture do
        facts.each_value do |fact|
          action = resource_action_for(fact.object, fact.action)
          changed_fields = action == :deleted ? [] : fact.changed_fields
          key = resource_event_key(fact.object, action)
          next if already_emitted?(key)
          next if merge_deferred_resource_event!(
            chain,
            fact,
            action,
            changed_fields:
          )

          remove_deferred_resource_events!(
            chain,
            fact.object,
            action: resource_action_for(fact.object, nil) ? nil : action
          )
          chain.defer_resource_event!(
            action,
            fact.object,
            owner: fact.owner,
            vps: fact.vps,
            changed_fields:,
            changes: fact.changes
          )
        end
      end
    end

    def merge_deferred_resource_event!(chain, fact, action, changed_fields:)
      operations = VpsAdmin::API::Events::ResourceOperations
      event_type = operations.ensure_event_type!(
        fact.object.class.base_class,
        action
      )
      descriptor = Array(chain.deferred_result_events).detect do |item|
        item['event_type'] == event_type &&
          item['source_class'] == fact.object.class.base_class.name &&
          item.dig('payload', 'resource_id') ==
            operations.resource_id_for(fact.object)
      end
      return false unless descriptor

      resource_payload = operations.payload_for(
        action,
        fact.object,
        changed_fields:,
        changes: fact.changes
      ).deep_stringify_keys
      descriptor['payload'] = merge_resource_payloads(
        resource_payload,
        descriptor.fetch('payload', {}).deep_stringify_keys
      )
      true
    end

    def merge_resource_payloads(observed, declared)
      observed.merge(declared).tap do |payload|
        payload['changed_fields'] = (
          Array(observed['changed_fields']) +
          Array(declared['changed_fields'])
        ).uniq.sort
        payload['changes'] = merge_payload_changes(
          observed.fetch('changes', {}),
          declared.fetch('changes', {})
        )
      end
    end

    def merge_payload_changes(observed, declared)
      observed.merge(declared) do |_field, observed_change, declared_change|
        observed_change.merge(declared_change)
      end
    end

    def consume!
      @entries.clear
      @pending_updates.clear
    end

    protected

    def resolved_facts
      @entries.each_value.with_object({}) do |entry, ret|
        resolved = resolve(entry)
        next unless resolved

        action, changed_fields, changes = resolved
        key = resource_key(entry.object)
        ret[key] = merge_fact(
          ret[key],
          Fact.new(
            action:,
            object: entry.object,
            owner: entry.owner,
            vps: entry.vps,
            changed_fields:,
            changes:
          )
        )
      end
    end

    def merge_confirmation_facts!(facts, chain)
      chain.transactions.includes(:transaction_confirmations).order(:id).each do |transaction|
        transaction.transaction_confirmations.sort_by(&:id).each do |confirmation|
          action = CONFIRM_ACTIONS[confirmation.confirm_type]
          next unless action

          object = confirmation_object(confirmation, action:)
          next unless object && records_model?(object, action)

          operations = VpsAdmin::API::Events::ResourceOperations
          vps = operations.related_vps(object)
          key = resource_key(object)
          previous = facts[key]
          facts[key] = merge_fact(
            previous,
            Fact.new(
              action:,
              object:,
              owner: operations.resource_owner(object, vps:),
              vps:,
              changed_fields: confirmation_changed_fields(confirmation),
              changes: confirmation_changes(
                confirmation,
                object,
                previous:
              )
            )
          )
        end
      end
    end

    def merge_fact(old, new)
      return new unless old

      action =
        if old.action == :created || new.action == :created
          :created
        elsif old.action == :deleted || new.action == :deleted
          :deleted
        else
          :updated
        end

      Fact.new(
        action:,
        object: new.object,
        owner: old.owner || new.owner,
        vps: old.vps || new.vps,
        changed_fields: (old.changed_fields + new.changed_fields).uniq.sort,
        changes: merge_changes(old.changes, new.changes)
      )
    end

    def merge_changes(old, new)
      old.to_h.merge(new.to_h) do |_field, previous, current|
        {}.tap do |change|
          if previous.has_key?(:old)
            change[:old] = previous[:old]
          elsif current.has_key?(:old)
            change[:old] = current[:old]
          end

          if current.has_key?(:new)
            change[:new] = current[:new]
          elsif previous.has_key?(:new)
            change[:new] = previous[:new]
          end
        end
      end
    end

    def confirmation_object(confirmation, action:)
      klass = confirmation.class_name.safe_constantize
      return unless klass && klass < ::ApplicationRecord
      return unless records_model_class?(klass, action)

      klass.unscoped.find_by(confirmation.row_pks)
    end

    def confirmation_changed_fields(confirmation)
      changes = confirmation.attr_changes

      if changes.is_a?(Hash)
        changes.keys.map(&:to_s)
      elsif changes
        [changes.to_s]
      else
        []
      end
    end

    def confirmation_changes(confirmation, object, previous:)
      attrs = confirmation.attr_changes

      case confirmation.confirm_type
      when 'edit_before_type'
        return {} unless attrs.is_a?(Hash)

        attrs.to_h do |field, value|
          field = field.to_s
          change = { old: cast_confirmation_value(object, field, value) }
          unless predicted_change(previous, field)&.has_key?(:new)
            change[:new] = object[field]
          end
          [field, change]
        end
      when 'edit_after_type'
        return {} unless attrs.is_a?(Hash)

        attrs.to_h do |field, value|
          field = field.to_s
          [
            field,
            {
              old: predicted_value(previous, object, field),
              new: cast_confirmation_value(object, field, value)
            }
          ]
        end
      when 'increment_type', 'decrement_type'
        counter_confirmation_changes(
          confirmation,
          object,
          previous:
        )
      else
        {}
      end
    end

    def counter_confirmation_changes(confirmation, object, previous:)
      attrs =
        if confirmation.attr_changes.is_a?(Hash)
          confirmation.attr_changes
        elsif confirmation.attr_changes
          { confirmation.attr_changes => 1 }
        else
          {}
        end
      direction = confirmation.confirm_type == 'increment_type' ? 1 : -1

      attrs.to_h do |field, delta|
        field = field.to_s
        old_value = predicted_value(previous, object, field)
        delta = cast_confirmation_value(object, field, delta)
        new_value = old_value.nil? ? nil : old_value + (direction * delta)
        [field, { old: old_value, new: new_value }]
      end
    end

    def predicted_value(previous, object, field)
      change = predicted_change(previous, field)
      return change[:new] if change&.has_key?(:new)

      object[field]
    end

    def predicted_change(previous, field)
      previous&.changes&.[](field)
    end

    def cast_confirmation_value(object, field, value)
      object.class.type_for_attribute(field).cast(value)
    end

    def resource_key(object)
      [
        object.class.base_class.name,
        VpsAdmin::API::Events::ResourceOperations.resource_id_for(object)
      ]
    end

    def resource_event_key(object, action)
      [*resource_key(object), action.to_s]
    end

    def already_emitted?(key)
      event_id = @already_emitted[key]
      return false unless event_id

      resource_type, resource_id, action = key
      resource_class = resource_type.safe_constantize
      event_type =
        if resource_class
          VpsAdmin::API::Events::ResourceOperations.event_name(action, resource_class)
        end
      event = ::Event.find_by(
        id: event_id,
        event_type:,
        source_class: resource_type
      )
      return true if event &&
                     event.parameters['resource_id'] == resource_id

      @already_emitted.delete(key)
      false
    end

    def resource_action_for(object, fallback)
      resource_action_for_model(object.class.base_class, fallback)
    end

    def resource_action_for_model(model, fallback)
      return fallback unless @resource_action

      model_name = model.base_class.name
      if @resource_action_model_names == :all ||
         @resource_action_model_names.include?(model_name)
        @resource_action
      else
        fallback
      end
    end

    def remove_deferred_resource_events!(chain, object, action:)
      descriptors = chain.deferred_result_events
      return unless descriptors

      resource_type, resource_id = resource_key(object)
      expected_event_type =
        if action
          VpsAdmin::API::Events::ResourceOperations.event_name(action, object)
        end
      descriptors.reject! do |descriptor|
        next false unless descriptor['source_class'] == resource_type &&
                          descriptor.dig('payload', 'resource_id') == resource_id
        next false unless descriptor['event_type'] == expected_event_type ||
                          VpsAdmin::API::Events::ResourceOperations.resource_event?(
                            descriptor['event_type']
                          )

        action.nil? ||
          descriptor['event_type'] ==
            VpsAdmin::API::Events::ResourceOperations.event_name(
              action,
              object
            )
      end
    end

    def merge(old, action, object, owner, vps, observed_fields)
      initially_persisted = old ? old.initially_persisted : action != :created
      initial_values = old ? old.initial_values : initial_values_for(object)
      field_states = old ? old.field_states.dup : {}

      observed_fields.each do |field, (before_value, observed_value)|
        previous = field_states[field]
        effective_before =
          if previous
            previous.before_value
          else
            merged_before_value(
              action,
              initially_persisted,
              initial_values,
              field,
              before_value
            )
          end
        observed_values =
          if previous
            [*previous.observed_values, observed_value]
          else
            [observed_value]
          end

        field_states[field] = FieldState.new(
          before_value: effective_before,
          observed_values: observed_values.uniq
        )
      end

      Entry.new(
        initially_persisted:,
        initial_values:,
        object:,
        owner: owner || old&.owner,
        vps: vps || old&.vps,
        field_states:
      )
    end

    def observed_fields_for(action, object, changed_fields, before_values)
      return {} if action == :deleted || changed_fields.empty?

      row = persisted_row(object, changed_fields)
      return {} unless row

      normalized_before_values =
        (before_values || {}).to_h do |field, value|
          [field.to_s, snapshot_value(value)]
        end

      changed_fields.to_h do |field|
        observed_value = snapshot_value(row[field])
        before_value =
          if action == :created
            NONEXISTENT_VALUE
          elsif normalized_before_values.has_key?(field)
            normalized_before_values[field]
          elsif object.has_attribute?(field) && object[field] != observed_value
            snapshot_value(object[field])
          else
            UNKNOWN_VALUE
          end

        [field, [before_value, observed_value]]
      end
    end

    def merged_before_value(
      action,
      initially_persisted,
      initial_values,
      field,
      before_value
    )
      if initially_persisted && action == :created && initial_values.has_key?(field)
        return initial_values[field]
      end

      return before_value unless before_value.equal?(UNKNOWN_VALUE)

      initial_values.fetch(field, UNKNOWN_VALUE)
    end

    def resolve(entry)
      fields = entry.field_states.keys
      row = persisted_row(entry.object, fields)

      unless row
        if entry.initially_persisted
          fields = VpsAdmin::API::Events::ResourceOperations
                   .auditable_attribute_names(entry.object.class.base_class)
          changes = fields.to_h do |field|
            [field, { old: entry.initial_values[field] }]
          end
          return [:deleted, fields, changes]
        end

        return
      end

      changed_fields = entry.field_states.filter_map do |field, state|
        final_value = row[field]
        next unless state.observed_values.any? { |value| value == final_value }
        next if !state.before_value.equal?(UNKNOWN_VALUE) &&
                !state.before_value.equal?(NONEXISTENT_VALUE) &&
                state.before_value == final_value

        field
      end.sort

      if entry.initially_persisted
        return if changed_fields.empty?

        changes = changed_fields.to_h do |field|
          before_value = entry.field_states.fetch(field).before_value
          [
            field,
            { new: row[field] }.tap do |change|
              unless before_value.equal?(UNKNOWN_VALUE) ||
                     before_value.equal?(NONEXISTENT_VALUE)
                change[:old] = before_value
              end
            end
          ]
        end
        [:updated, changed_fields, changes]
      else
        [:created, changed_fields, {}]
      end
    end

    def initial_values_for(object)
      object.attribute_names.to_h do |field|
        [field.to_s, snapshot_value(object[field])]
      end
    end

    def snapshot_value(value)
      if value.respond_to?(:deep_dup)
        value.deep_dup
      elsif value.duplicable?
        value.dup
      else
        value
      end
    end

    def records_model?(object, action)
      records_model_class?(object.class, action)
    end

    def records_model_class?(model, action)
      model_name = model.base_class.name
      published_action = resource_action_for_model(model, action)
      return false unless VpsAdmin::API::Events::ResourceOperations.catalogued?(
        model,
        published_action
      )
      # A transaction chain can change public resources other than the API
      # action's target through nested chains and confirmations. Capture every
      # catalogued model; @resource_action_model_names still limits the
      # action-target CRUD intent override to the declared target model.
      return true if @transaction_chain

      @model_names == :all || @model_names.include?(model_name)
    end

    def pending_update_key(object)
      [
        object.class.base_class.name,
        object.id,
        object.object_id
      ]
    end

    def persisted_row(object, fields)
      relation = persisted_relation(object)
      if fields.empty?
        relation.select(object.class.base_class.primary_key).first
      else
        relation.select(*fields).first
      end
    end

    def persisted_relation(object)
      model = object.class.base_class
      resource_id =
        VpsAdmin::API::Events::ResourceOperations.resource_id_for(object)
      conditions =
        if resource_id.is_a?(Hash)
          resource_id
        else
          { model.primary_key => resource_id }
        end

      model.unscoped.where(conditions)
    end

    def record_existing_event(event)
      operations = VpsAdmin::API::Events::ResourceOperations
      return unless operations.resource_event?(event)

      type = VpsAdmin::API::Events.type_for(event.event_type)
      action = type.resource.fetch(:action)
      @already_emitted[[
        event.source_class,
        event.parameters['resource_id'],
        action
      ]] = event.id
    end

    def without_capture(&)
      VpsAdmin::API::Events::ActionPolicies.with_recorder(nil, &)
    end
  end

  module ActionExecution
    def safe_exec
      policies = VpsAdmin::API::Events::ActionPolicies
      policy = policies.for(self.class)

      if policy&.records_transaction_chain_resources?
        recorder = VpsAdmin::API::Events::ActionPolicies::Recorder.new(policy)
        response = policies.with_recorder(recorder) { super }

        recorder.emit! if recorder.pending?

        return response
      end

      return super unless policy&.records_resources?

      recorder = VpsAdmin::API::Events::ActionPolicies::Recorder.new(policy)
      response = nil

      if policy.atomic
        ::ApplicationRecord.transaction(requires_new: true) do
          VpsAdmin::API::Events::ActionPolicies.with_recorder(recorder) do
            response = super
          end

          raise ::ActiveRecord::Rollback unless response.first

          recorder.emit!
        end
      else
        begin
          VpsAdmin::API::Events::ActionPolicies.with_recorder(recorder) do
            response = super
          end
        ensure
          if policy.emit_on_failure && (response.nil? || !response.first)
            recorder.emit!
          end
        end
        recorder.emit! if response&.first
      end

      response
    end
  end

  module OperationExecution
    def run(*args, **kwargs)
      policies = VpsAdmin::API::Events::ActionPolicies
      policy = policies.for_operation(self)

      unless policy
        raise "missing event policy for operation #{name}"
      end

      policies.capture(policy) { super(*args, **kwargs) }
    end
  end

  module OAuth2Execution
    def handle_get_authorize(**kwargs)
      capture_oauth2('oauth2.authorize_get') { super(**kwargs) }
    end

    def handle_post_authorize(**kwargs)
      capture_oauth2('oauth2.authorize_post') { super(**kwargs) }
    end

    def get_tokens(authorization, sinatra_request)
      capture_oauth2('oauth2.issue_tokens') do
        super(authorization, sinatra_request)
      end
    end

    def refresh_tokens(authorization, sinatra_request)
      capture_oauth2('oauth2.refresh_tokens') do
        super(authorization, sinatra_request)
      end
    end

    def handle_post_revoke(sinatra_request, token, token_type_hint: nil, client: nil)
      capture_oauth2('oauth2.revoke') do
        super(
          sinatra_request,
          token,
          token_type_hint:,
          client:
        )
      end
    end

    protected

    def capture_oauth2(name, &)
      policies = VpsAdmin::API::Events::ActionPolicies
      policies.capture(policies.external_policy(name), &)
    end
  end

  module NotificationCallbackExecution
    def apply_sms_gateway_callback!(*args, **kwargs)
      policies = VpsAdmin::API::Events::ActionPolicies

      policies.capture(
        policies.external_policy('notifications.sms_callback')
      ) { super(*args, **kwargs) }
    end
  end

  @explicit = {}
  @operation_explicit = {}
  @external = {}
  @delete_cascades = {}

  module_function

  def register(
    action_class_name,
    kind:,
    models: [],
    reason: nil,
    atomic: true,
    emit_on_failure: false
  )
    @explicit[action_class_name.to_s] = Policy.new(
      kind:,
      models: models == :all ? :all : Array(models).map(&:to_s).freeze,
      reason:,
      atomic:,
      emit_on_failure:
    )
  end

  def register_operation(
    operation_class_name,
    kind:,
    models: [],
    reason: nil,
    atomic: true,
    emit_on_failure: false
  )
    @operation_explicit[operation_class_name.to_s] = Policy.new(
      kind:,
      models: models == :all ? :all : Array(models).map(&:to_s).freeze,
      reason:,
      atomic:,
      emit_on_failure:
    )
  end

  def register_external(
    name,
    kind:,
    models: [],
    reason: nil,
    atomic: false,
    emit_on_failure: false
  )
    @external[name.to_s] = Policy.new(
      kind:,
      models: models == :all ? :all : Array(models).map(&:to_s).freeze,
      reason:,
      atomic:,
      emit_on_failure:
    )
  end

  def register_delete_cascade(model_name, *associations)
    @delete_cascades[model_name.to_s] = associations.map(&:to_sym).freeze
  end

  def delete_cascades
    @delete_cascades.dup.freeze
  end

  def for(action)
    explicit = @explicit[action.name]
    return explicit if explicit

    method = action.http_method.to_sym
    return Policy.new(kind: :read, models: [], reason: nil, atomic: false) unless MUTATING_HTTP_METHODS.include?(method)

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

  def for_operation(operation)
    @operation_explicit[operation.name]
  end

  def operation_policies
    @operation_explicit.dup.freeze
  end

  def external_policy(name)
    @external.fetch(name.to_s)
  end

  def external_policies
    @external.dup.freeze
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

  # Active Record lifecycle callbacks cannot see update_all/delete_all/counter
  # writes. Callers at the known mutation boundary use this explicit helper
  # after the SQL succeeds, while the surrounding recorder transaction still
  # controls whether the resulting facts are emitted or rolled back.
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
    associations = @delete_cascades[key.first]
    return [] unless associations

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
    VpsAdmin::API::Authentication::OAuth2Config.prepend(OAuth2Execution)
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
end

action_policies = VpsAdmin::API::Events::ActionPolicies

action_policies.register(
  'VpsAdmin::API::Resources::SecurityAdvisory::Publish',
  kind: :resource,
  models: %w[
    SecurityAdvisory
    SecurityAdvisoryUser
    SecurityAdvisoryVps
  ],
  atomic: false,
  emit_on_failure: true
)
action_policies.register(
  'VpsAdmin::API::Resources::SecurityAdvisoryUpdate::Create',
  kind: :resource,
  models: %w[
    SecurityAdvisory
    SecurityAdvisoryTranslation
    SecurityAdvisoryUpdate
  ],
  atomic: false,
  emit_on_failure: true
)
action_policies.register(
  'VpsAdmin::API::Resources::OutageUpdate::Create',
  kind: :resource,
  models: %w[
    Outage
    OutageExport
    OutageTranslation
    OutageUpdate
    OutageUser
    OutageVps
  ]
)
action_policies.register(
  'VpsAdmin::API::Resources::IncidentReport::Create',
  kind: :resource,
  models: %w[IncidentReport],
  atomic: false,
  emit_on_failure: true
)
action_policies.register(
  'VpsAdmin::API::Resources::User::Update',
  kind: :resource,
  models: %w[User],
  atomic: false,
  emit_on_failure: true
)

action_policies.register(
  'VpsAdmin::API::Resources::Cluster::Search',
  kind: :read,
  reason: 'POST is used for a read-only cluster search',
  atomic: false
)
action_policies.register(
  'VpsAdmin::API::Resources::ApiServer::UnlockTransactionSigningKey',
  kind: :runtime_state,
  reason: 'changes in-memory key state and persists no resource',
  atomic: false
)
action_policies.register(
  'VpsAdmin::API::Resources::Event::Test',
  kind: :domain_event,
  reason: 'the action itself creates the requested test event',
  atomic: false
)
action_policies.register(
  'VpsAdmin::API::Resources::VPS::MaintenanceWindow::UpdateAll',
  kind: :domain_event,
  reason: 'emits vps.maintenance_windows_updated atomically',
  atomic: false
)

{
  'VpsAdmin::API::Resources::DatasetExpansion::RegisterExpanded' => %w[DatasetExpansion],
  'VpsAdmin::API::Resources::Event::Delivery::Retry' => %w[EventDelivery],
  'VpsAdmin::API::Resources::MigrationPlan::Start' => %w[MigrationPlan VpsMigration],
  'VpsAdmin::API::Resources::MigrationPlan::Cancel' =>
    %w[MigrationPlan VpsMigration],
  'VpsAdmin::API::Resources::MonitoredEvent::Acknowledge' => %w[MonitoredEvent],
  'VpsAdmin::API::Resources::MonitoredEvent::Ignore' => %w[MonitoredEvent],
  'VpsAdmin::API::Resources::Network::AddAddresses' => %w[IpAddress],
  'VpsAdmin::API::Resources::Node::Evacuate' => %w[MigrationPlan VpsMigration],
  'VpsAdmin::API::Resources::Outage::RebuildAffectedVps' =>
    %w[OutageVps OutageExport OutageUser],
  'VpsAdmin::API::Resources::SecurityAdvisory::RebuildAffectedVps' =>
    %w[SecurityAdvisoryVps SecurityAdvisoryUser],
  'VpsAdmin::API::Resources::SystemConfig::Update' => %w[SysConfig],
  'VpsAdmin::API::Resources::TransactionChain::NotifyWhenDone' => %w[
    EventRoute
    EventRouteMatcher
    NotificationReceiver
    NotificationReceiverTarget
    NotificationTarget
  ],
  'VpsAdmin::API::Resources::User::TotpDevice::Confirm' => %w[UserTotpDevice],
  'VpsAdmin::API::Resources::UserSession::Close' => %w[UserSession],
  'VpsAdmin::API::Resources::Webauthn::Registration::Begin' =>
    %w[User WebauthnChallenge],
  'VpsAdmin::API::Resources::Webauthn::Registration::Finish' =>
    %w[WebauthnCredential WebauthnChallenge],
  'VpsAdmin::API::Resources::Webauthn::Authentication::Begin' =>
    %w[WebauthnChallenge],
  'VpsAdmin::API::Resources::Webauthn::Authentication::Finish' =>
    %w[WebauthnCredential WebauthnChallenge AuthToken],
  'VpsAdmin::API::Resources::WebuiUserSetting::Set' => %w[WebuiUserSetting],
  'VpsAdmin::API::Resources::WebuiUserSetting::Delete' => %w[WebuiUserSetting]
}.each do |action_class_name, models|
  action_policies.register(action_class_name, kind: :resource, models:)
end

{
  'VpsAdmin::API::Resources::NewsLog::Create' =>
    %w[NewsLog NewsLogTranslation],
  'VpsAdmin::API::Resources::NewsLog::Update' =>
    %w[NewsLog NewsLogTranslation],
  'VpsAdmin::API::Resources::NewsLog::Delete' =>
    %w[NewsLog NewsLogTranslation],
  'VpsAdmin::API::Resources::Outage::Create' =>
    %w[Outage OutageTranslation OutageUpdate],
  'VpsAdmin::API::Resources::Outage::Update' =>
    %w[Outage OutageTranslation],
  'VpsAdmin::API::Resources::SecurityAdvisory::Create' => %w[
    SecurityAdvisory
    SecurityAdvisoryCve
    SecurityAdvisoryTranslation
  ],
  'VpsAdmin::API::Resources::SecurityAdvisory::Update' => %w[
    SecurityAdvisory
    SecurityAdvisoryTranslation
  ],
  'VpsAdmin::API::Resources::SecurityAdvisory::NodeStatus::Create' => %w[
    SecurityAdvisory
    SecurityAdvisoryNodeStatus
    SecurityAdvisoryNodeStatusTranslation
  ],
  'VpsAdmin::API::Resources::SecurityAdvisory::NodeStatus::Update' => %w[
    SecurityAdvisory
    SecurityAdvisoryNodeStatus
    SecurityAdvisoryNodeStatusTranslation
  ],
  'VpsAdmin::API::Resources::SecurityAdvisory::NodeStatus::Delete' => %w[
    SecurityAdvisory
    SecurityAdvisoryNodeStatus
    SecurityAdvisoryNodeStatusTranslation
  ],
  'VpsAdmin::API::Resources::SecurityAdvisoryUpdate::Update' => %w[
    SecurityAdvisoryUpdate
    SecurityAdvisoryTranslation
  ],
  'VpsAdmin::API::Resources::SecurityAdvisoryUpdate::Delete' => %w[
    SecurityAdvisoryUpdate
    SecurityAdvisoryTranslation
  ]
}.each do |action_class_name, models|
  action_policies.register(action_class_name, kind: :resource, models:)
end

{
  'AuthToken' => %i[token],
  'ClusterResourcePackage' => %i[
    cluster_resource_package_items
    default_user_cluster_resource_packages
  ],
  'DnsRecord' => %i[update_token],
  'DnsServerZone' => %i[dns_server_zone_transfer_logs],
  'DnsZone' => %i[dns_zone_transfers dns_records dnssec_records],
  'Event' => %i[event_deliveries event_routing_contexts event_route_matches],
  'EventDelivery' => %i[event_delivery_attempts],
  'EventRoute' => %i[
    event_route_matchers
    event_route_time_intervals
    event_route_matches
  ],
  'Mailbox' => %i[mailbox_handlers],
  'MetricsAccessToken' => %i[token],
  'MonitoredEvent' => %i[monitored_event_states monitored_event_logs],
  'NewsLog' => %i[news_log_translations],
  'NodeEbpfProgram' => %i[program_objects program_links],
  'NodeKernelConfiguration' => %i[kernel_configuration_options],
  'NodeKernelEvent' => %i[sysctl_changes software_changes],
  'NodeKernelEvidence' => %i[
    kernel_parameters
    kernel_modules
    sysctls
    software_versions
    kernel_evidence_errors
  ],
  'NodeKernelHistoryState' => %i[kernel_history_gaps],
  'NodeKernelLivepatch' => %i[patches],
  'NotificationReceiver' => %i[
    notification_receiver_targets
    notification_receiver_actions
  ],
  'NotificationTarget' => %i[notification_receiver_targets],
  'OomReport' => %i[oom_report_usages oom_report_stats oom_report_tasks],
  'SecurityAdvisory' => %i[
    security_advisory_cves
    security_advisory_translations
    security_advisory_vpses
    security_advisory_users
  ],
  'SecurityAdvisoryNodeStatus' => %i[
    security_advisory_node_status_translations
  ],
  'SecurityAdvisoryUpdate' => %i[security_advisory_translations],
  'SingleSignOn' => %i[token],
  'User' => %i[
    user_notification_delivery_methods
    user_notification_rate_limits
    notification_rate_limit_states
  ],
  'UserDevice' => %i[token],
  'UserNamespaceMap' => %i[user_namespace_map_entries],
  'Vps' => %i[vps_mounts oom_report_counters export_mounts],
  'WebauthnChallenge' => %i[token]
}.each do |model_name, associations|
  action_policies.register_delete_cascade(model_name, *associations)
end

%w[
  Cluster
  Environment
  Location
  Node
  Pool
  VPS
].each do |resource_name|
  action_policies.register(
    "VpsAdmin::API::Resources::#{resource_name}::SetMaintenance",
    kind: :resource,
    models: %w[MaintenanceLock Environment Location Node Pool Vps]
  )
end

%w[
  ConfirmEmailVerification
  ConfirmSmsVerificationCode
  CreatePairingToken
].each do |action_name|
  action_policies.register(
    "VpsAdmin::API::Resources::NotificationTarget::#{action_name}",
    kind: :resource,
    models: %w[NotificationTarget]
  )
end

%w[
  SendEmailVerification
  SendSmsVerificationCode
].each do |action_name|
  action_policies.register(
    "VpsAdmin::API::Resources::NotificationTarget::#{action_name}",
    kind: :resource,
    models: %w[NotificationTarget],
    atomic: false
  )
end

%w[
  Change
  Registration
].each do |resource_name|
  action_policies.register(
    "VpsAdmin::API::Resources::UserRequest::#{resource_name}::Resolve",
    kind: :transaction_chain,
    reason: 'resolution is executed by a transaction chain',
    atomic: false
  )
end

# Operations run both from HaveAPI actions and from authentication providers,
# callbacks and background consumers. Every concrete operation is classified
# explicitly so a newly added operation cannot silently bypass event capture.
{
  'Authentication::Password' => %w[User AuthToken Token],
  'Authentication::ResetPassword' => %w[User AuthToken Token],
  'Authentication::Totp' => %w[UserTotpDevice AuthToken Token],
  'DatasetExpansion::ProcessEvent' => %w[
    Dataset
    DatasetExpansion
    DatasetExpansionEvent
    DatasetExpansionHistory
    DatasetInPool
    DatasetProperty
  ],
  'DnsTsigKey::Create' => %w[DnsTsigKey],
  'DnsTsigKey::Destroy' => %w[DnsTsigKey],
  'DnsZone::CreateSystem' => %w[DnsZone IpAddress],
  'DnsZone::DestroySystem' => %w[DnsZone],
  'Environment::Update' => %w[Environment EnvironmentUserConfig],
  'Environment::UpdateUserConfig' => %w[EnvironmentUserConfig],
  'HostIpAddress::Create' => %w[HostIpAddress],
  'LocationNetwork::Create' => %w[LocationNetwork Network],
  'LocationNetwork::Delete' => %w[LocationNetwork Network],
  'LocationNetwork::Update' => %w[LocationNetwork Network],
  'Node::ReconstructKernelEvents' => %w[
    NodeKernelEvent
    NodeKernelHistoryGap
    NodeKernelHistoryState
  ],
  'Node::ReconstructSystemStates' => %w[
    NodeSystemHistoryState
    NodeSystemState
  ],
  'Node::RecordKernelEvidence' => %w[
    NodeKernelEvent
    NodeKernelEvidence
    NodeSoftwareChange
    NodeSysctlChange
  ],
  'TotpDevice::Confirm' => %w[User UserTotpDevice],
  'TotpDevice::Create' => %w[UserTotpDevice],
  'TotpDevice::Delete' => %w[UserTotpDevice],
  'TotpDevice::Disable' => %w[UserTotpDevice],
  'TotpDevice::Enable' => %w[User UserTotpDevice],
  'TotpDevice::Update' => %w[UserTotpDevice],
  'UserSession::Close' => %w[
    UserSession
    Oauth2Authorization
    SingleSignOn
    Token
  ],
  'UserSession::CloseAll' => %w[
    UserSession
    Oauth2Authorization
    SingleSignOn
    Token
  ],
  'UserSession::CloseToken' => %w[UserSession Token],
  'UserSession::NewOAuth2Login' => %w[User UserSession UserDevice Token],
  'UserSession::NewTokenDetached' => %w[UserSession Token],
  'UserSession::NewTokenLogin' => %w[User UserSession Token]
}.each do |operation_name, models|
  action_policies.register_operation(
    "VpsAdmin::API::Operations::#{operation_name}",
    kind: :resource,
    models:
  )
end

%w[
  User::Login
  UserSession::NewBasicLogin
  UserSession::ResumeOAuth2
  UserSession::ResumeToken
].each do |operation_name|
  action_policies.register_operation(
    "VpsAdmin::API::Operations::#{operation_name}",
    kind: :internal_state,
    reason: 'per-request authentication counters and session state are bookkeeping',
    atomic: false
  )
end

%w[
  Dataset::FindByName
  Node::Pick
  User::CheckLogin
].each do |operation_name|
  action_policies.register_operation(
    "VpsAdmin::API::Operations::#{operation_name}",
    kind: :read,
    reason: 'operation does not persist state',
    atomic: false
  )
end

%w[
  User::FailedLogin
  User::IncompleteLogin
].each do |operation_name|
  action_policies.register_operation(
    "VpsAdmin::API::Operations::#{operation_name}",
    kind: :domain_event,
    reason: 'emits user.login_failed with authentication context',
    atomic: false
  )
end

%w[
  Dataset::Create
  Dataset::UpdateProperties
  DnsServerZone::Create
  DnsServerZone::Destroy
  DnsZone::CreateRecord
  DnsZone::CreateUser
  DnsZone::DestroyRecord
  DnsZone::DestroyUser
  DnsZone::DynamicUpdate
  DnsZone::Update
  DnsZone::UpdateRecord
  DnsZoneTransfer::Create
  DnsZoneTransfer::Destroy
  Export::AddHost
  Export::Create
  Export::DelHost
  Export::Destroy
  Export::EditHost
  Export::Update
  HostIpAddress::Destroy
  HostIpAddress::Update
  Vps::Create
  Vps::Migrate
  Vps::Passwd
  Vps::Reinstall
  Vps::SetFeatures
].each do |operation_name|
  action_policies.register_operation(
    "VpsAdmin::API::Operations::#{operation_name}",
    kind: :transaction_chain,
    reason: 'covered by transaction-chain operation lifecycle events',
    atomic: false
  )
end

oauth2_models = %w[
  AuthToken
  Oauth2Authorization
  SingleSignOn
  Token
  User
  UserDevice
  UserSession
  UserTotpDevice
].freeze

%w[
  oauth2.authorize_get
  oauth2.authorize_post
  oauth2.issue_tokens
  oauth2.refresh_tokens
  oauth2.revoke
].each do |surface|
  action_policies.register_external(
    surface,
    kind: :resource,
    models: oauth2_models,
    atomic: true
  )
end

action_policies.register_external(
  'notifications.sms_callback',
  kind: :internal_state,
  reason: 'delivery transport state must not create a routeable feedback event',
  atomic: false
)
action_policies.register_external(
  'webauthn.registration_new',
  kind: :read,
  reason: 'renders the registration page and does not persist state',
  atomic: false
)
