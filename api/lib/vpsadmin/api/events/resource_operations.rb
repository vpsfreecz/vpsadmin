module VpsAdmin::API::Events::ResourceOperations
  ACTIONS = %w[created updated deleted].freeze

  module_function

  def emit!(action, object, owner: nil, vps: nil, changed_fields: [], occurred_at: nil)
    action = action.to_s
    raise ArgumentError, "unsupported resource event action #{action.inspect}" unless ACTIONS.include?(action)

    actor = ::User.current
    session = ::UserSession.current
    resource_type = object.class.base_class.name
    resource_id = object.id
    vps ||= related_vps(object)
    owner ||= resource_owner(object, vps:)
    owner ||= actor if actor&.role == :user

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
    return object if object.is_a?(::User)

    nil
  end

  def related_vps(object)
    object if object.is_a?(::Vps)
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

VpsAdmin::API::Events.define do
  {
    'resource.created' => 'Resource created',
    'resource.updated' => 'Resource updated',
    'resource.deleted' => 'Resource deleted'
  }.each do |event_name, label|
    event event_name,
          label:,
          category: 'resource',
          severity: :info,
          roles: %i[account admin],
          default_routed: false do
      fields(
        resource_type: {
          description: 'ActiveRecord class of the affected resource',
          type: :string
        },
        resource_id: {
          description: 'ID of the affected resource',
          type: :integer
        },
        action: {
          description: 'Completed create, update or delete action',
          type: :string,
          choices: VpsAdmin::API::Events::ResourceOperations::ACTIONS
        },
        actor_user_id: {
          description: 'ID of the user who performed the action',
          type: :integer
        },
        actor_user_login: {
          description: 'Login of the user who performed the action',
          type: :string
        },
        admin_user_id: {
          description: 'ID of the administrator behind an impersonated session',
          type: :integer
        },
        user_session_id: {
          description: 'ID of the user session associated with the event',
          type: :integer
        },
        changed_fields: {
          description: 'Names of fields submitted to a successful update',
          type: :string_list
        }
      )
    end
  end
end
