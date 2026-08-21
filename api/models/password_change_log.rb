class PasswordChangeLog < ApplicationRecord
  belongs_to :user
  belongs_to :user_session, optional: true

  validates :source, inclusion: {
    in: VpsAdmin::API::PasswordChanges::SOURCES.map(&:to_s)
  }

  def user_session_owned_by_user
    return false unless user_session_id

    user_session&.user_id == user_id
  end
end
