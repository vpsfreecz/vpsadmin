module VpsAdmin::API::Events::ActionPolicies
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
end
