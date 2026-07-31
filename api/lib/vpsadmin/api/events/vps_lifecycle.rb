module VpsAdmin::API::Events::VpsLifecycle
  module_function

  def emit_expiration_changed!(vps, previous_expiration:, reason: nil, changed_by: nil)
    emit_vps!(
      'vps.expiration_changed',
      vps,
      subject: "Expiration changed for VPS ##{vps.id}",
      payload: {
        previous_expiration_date: timestamp(previous_expiration),
        expiration_date: timestamp(vps.expiration_date),
        remind_after_date: timestamp(vps.remind_after_date),
        state: vps.object_state,
        reason:,
        changed_by_id: changed_by&.id,
        changed_by_login: changed_by&.login
      }
    )
  end

  def emit_expiration_reached!(vps, observed_at:, target_state:)
    emit_vps!(
      'vps.expiration_reached',
      vps,
      subject: "Expiration reached for VPS ##{vps.id}",
      occurred_at: observed_at,
      payload: {
        expiration_date: timestamp(vps.expiration_date),
        observed_at: timestamp(observed_at),
        state: vps.object_state,
        target_state: target_state.to_s,
        trigger: 'lifetime_scheduler'
      }
    )
  end

  def emit_expiration_processing_started!(vps, observed_at:, previous_state:, target_state:,
                                          transaction_chain: nil)
    emit_vps!(
      'vps.expiration_processing_started',
      vps,
      subject: "Expiration processing started for VPS ##{vps.id}",
      occurred_at: observed_at,
      payload: {
        expiration_date: timestamp(vps.expiration_date),
        processing_started_at: timestamp(observed_at),
        previous_state: previous_state.to_s,
        target_state: target_state.to_s,
        transaction_chain_id: transaction_chain&.id,
        trigger: 'lifetime_scheduler'
      }.compact
    )
  end

  def emit_runtime!(event_type, vps, occurred_at:, source: nil, payload: {})
    emit_vps!(
      event_type,
      vps,
      source: source || vps,
      subject: "#{VpsAdmin::API::Events.type_for(event_type)&.label} for VPS ##{vps.id}",
      occurred_at:,
      payload: {
        node_id: vps.node_id,
        node_name: vps.node.domain_name,
        runtime_event_type: event_type.delete_prefix('vps.runtime_')
      }.merge(payload)
    )
  end

  def emit_maintenance_window_updated!(vps, window, previous:)
    changed_by = ::User.current
    emit_vps!(
      'vps.maintenance_window_updated',
      vps,
      source: window,
      subject: "Maintenance window updated for VPS ##{vps.id}",
      payload: {
        maintenance_window_id: window.id,
        weekday: window.weekday,
        previous_is_open: previous.fetch(:is_open),
        previous_opens_at: previous[:opens_at],
        previous_closes_at: previous[:closes_at],
        is_open: window.is_open,
        opens_at: window.opens_at,
        closes_at: window.closes_at,
        changed_by_id: changed_by&.id,
        changed_by_login: changed_by&.login
      }
    )
  end

  def emit_maintenance_windows_updated!(vps, changed_fields:)
    changed_by = ::User.current
    emit_vps!(
      'vps.maintenance_windows_updated',
      vps,
      subject: "Maintenance windows updated for VPS ##{vps.id}",
      payload: {
        changed_fields: changed_fields.map(&:to_s).sort,
        window_count: vps.vps_maintenance_windows.count,
        changed_by_id: changed_by&.id,
        changed_by_login: changed_by&.login
      }
    )
  end

  def emit_user_data!(event_type, user_data, changed_fields:)
    changed_by = ::User.current
    VpsAdmin::API::Events.emit!(
      event_type,
      user: user_data.user,
      source_class: user_data.class.name,
      source_id: user_data.id,
      subject: "#{VpsAdmin::API::Events.type_for(event_type)&.label}: #{user_data.label}",
      payload: {
        user_data_id: user_data.id,
        user_id: user_data.user_id,
        user_login: user_data.user.login,
        label: user_data.label,
        format: user_data.format,
        changed_fields: changed_fields.map(&:to_s).sort,
        changed_by_id: changed_by&.id,
        changed_by_login: changed_by&.login
      }
    )
  end

  def emit_vps!(event_type, vps, subject:, payload:, source: vps, occurred_at: nil)
    VpsAdmin::API::Events.emit!(
      event_type,
      user: vps.user,
      vps:,
      source:,
      subject:,
      payload: {
        vps_id: vps.id,
        vps_hostname: vps.hostname
      }.merge(payload),
      occurred_at:
    )
  end

  def timestamp(value)
    value&.utc&.iso8601
  end
end

VpsAdmin::API::Events.define do
  event 'vps.expiration_changed',
        label: 'VPS expiration changed',
        category: 'vps',
        severity: :info,
        audience: :account,
        roles: %i[account admin],
        default_routed: false do
    fields(
      vps_id: { description: 'ID of the affected VPS', type: :integer },
      vps_hostname: { description: 'Hostname of the affected VPS', type: :string },
      previous_expiration_date: { description: 'Previous expiration date', type: :datetime },
      expiration_date: { description: 'New expiration date', type: :datetime },
      remind_after_date: { description: 'New reminder suppression date', type: :datetime },
      state: { description: 'Current VPS lifecycle state', type: :string },
      reason: { description: 'Reason supplied with the expiration change', type: :string },
      changed_by_id: { description: 'ID of the user who made the change', type: :integer },
      changed_by_login: { description: 'Login of the user who made the change', type: :string }
    )
  end

  {
    'vps.expiration_reached' => ['VPS expiration reached', :warning],
    'vps.expiration_processing_started' => ['VPS expiration processing started', :info]
  }.each do |event_name, (label, severity)|
    event event_name,
          label:,
          category: 'vps',
          severity:,
          audience: :account,
          roles: %i[account admin],
          default_routed: false do
      fields(
        vps_id: { description: 'ID of the affected VPS', type: :integer },
        vps_hostname: { description: 'Hostname of the affected VPS', type: :string },
        expiration_date: { description: 'Expiration date observed by the scheduler', type: :datetime },
        observed_at: { description: 'Time when expiration was observed', type: :datetime },
        processing_started_at: {
          description: 'Time when expiration processing was queued',
          type: :datetime
        },
        state: { description: 'Lifecycle state observed by the scheduler', type: :string },
        previous_state: { description: 'Lifecycle state before processing', type: :string },
        target_state: { description: 'Lifecycle state requested by the scheduler', type: :string },
        transaction_chain_id: { description: 'ID of the queued lifecycle transaction chain', type: :integer },
        trigger: { description: 'Subsystem that produced the event', type: :string }
      )
    end
  end

  {
    'vps.runtime_halted' => ['VPS runtime halted', :info],
    'vps.runtime_rebooted' => ['VPS runtime rebooted', :info],
    'vps.runtime_oom_stopped' => ['VPS runtime stopped after OOM abuse', :warning],
    'vps.runtime_oom_restarted' => ['VPS runtime restarted after OOM abuse', :warning]
  }.each do |event_name, (label, severity)|
    event event_name,
          label:,
          category: 'vps',
          severity:,
          audience: :account,
          roles: %i[account admin],
          default_routed: false do
      fields(
        vps_id: { description: 'ID of the affected VPS', type: :integer },
        vps_hostname: { description: 'Hostname of the affected VPS', type: :string },
        node_id: { description: 'ID of the node reporting the runtime event', type: :integer },
        node_name: { description: 'Name of the node reporting the runtime event', type: :string },
        runtime_event_type: { description: 'Normalized runtime event type', type: :string },
        producer_event_id: {
          description: 'Stable node-assigned identifier used to deduplicate runtime event delivery',
          type: :string
        },
        incident_report_id: { description: 'ID of the related incident report', type: :integer }
      )
    end
  end

  event 'vps.maintenance_window_updated',
        label: 'VPS maintenance window updated',
        category: 'vps',
        severity: :info,
        audience: :account,
        roles: %i[account admin],
        default_routed: false do
    fields(
      vps_id: { description: 'ID of the affected VPS', type: :integer },
      vps_hostname: { description: 'Hostname of the affected VPS', type: :string },
      maintenance_window_id: { description: 'ID of the maintenance window', type: :integer },
      weekday: { description: 'Week day represented by the window', type: :integer },
      previous_is_open: { description: 'Whether the window was previously open', type: :boolean },
      previous_opens_at: { description: 'Previous opening minute of day', type: :integer },
      previous_closes_at: { description: 'Previous closing minute of day', type: :integer },
      is_open: { description: 'Whether the window is open after the change', type: :boolean },
      opens_at: { description: 'Opening minute of day after the change', type: :integer },
      closes_at: { description: 'Closing minute of day after the change', type: :integer },
      changed_by_id: { description: 'ID of the user who changed the window', type: :integer },
      changed_by_login: { description: 'Login of the user who changed the window', type: :string }
    )
  end

  event 'vps.maintenance_windows_updated',
        label: 'VPS maintenance windows updated',
        category: 'vps',
        severity: :info,
        audience: :account,
        roles: %i[account admin],
        default_routed: false do
    fields(
      vps_id: { description: 'ID of the affected VPS', type: :integer },
      vps_hostname: { description: 'Hostname of the affected VPS', type: :string },
      changed_fields: { description: 'Maintenance-window fields changed on every day', type: :string_list },
      window_count: { description: 'Number of maintenance windows updated', type: :integer },
      changed_by_id: { description: 'ID of the user who changed the windows', type: :integer },
      changed_by_login: { description: 'Login of the user who changed the windows', type: :string }
    )
  end

  {
    'vps.user_data_created' => 'VPS user data created',
    'vps.user_data_updated' => 'VPS user data updated',
    'vps.user_data_deleted' => 'VPS user data deleted'
  }.each do |event_name, label|
    event event_name,
          label:,
          category: 'vps',
          severity: :info,
          audience: :account,
          roles: %i[account admin],
          default_routed: false do
      fields(
        user_data_id: { description: 'ID of the VPS user-data record', type: :integer },
        user_id: { description: 'ID of the user-data owner', type: :integer },
        user_login: { description: 'Login of the user-data owner', type: :string },
        label: { description: 'User-visible user-data label', type: :string },
        format: { description: 'User-data format', type: :string },
        changed_fields: { description: 'Names of fields changed by the operation', type: :string_list },
        changed_by_id: { description: 'ID of the user who changed the record', type: :integer },
        changed_by_login: { description: 'Login of the user who changed the record', type: :string }
      )
    end
  end
end
