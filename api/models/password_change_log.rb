class PasswordChangeLog < ApplicationRecord
  belongs_to :user
  belongs_to :user_session, optional: true
  belongs_to :user_agent, optional: true

  validates :source, inclusion: {
    in: VpsAdmin::API::PasswordChanges::SOURCES.map(&:to_s)
  }

  def user_session_owned_by_user
    return false unless user_session_id

    user_session&.user_id == user_id
  end

  def user_agent_string
    user_agent&.agent
  end

  def visible_client_ip_addr
    client_details_visible? ? client_ip_addr : nil
  end

  def visible_client_ip_ptr
    client_details_visible? ? client_ip_ptr : nil
  end

  def visible_user_agent_string
    client_details_visible? ? user_agent_string : nil
  end

  def client_details_visible?
    viewer = ::User.current
    return true if viewer&.role == :admin
    return false unless viewer&.id == user_id

    user_session_id.nil? || user_session_owned_by_user
  end

  def attach_user_session!(session)
    with_lock do
      if session.user_id != user_id
        raise ArgumentError, 'user session belongs to another user'
      end
      if user_session_id && user_session_id != session.id
        raise ArgumentError, 'password change already has a user session'
      end

      update!(user_session: session) unless user_session_id
    end

    self
  end
end
