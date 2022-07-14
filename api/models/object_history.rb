class ObjectHistory < ActiveRecord::Base
  belongs_to :tracked_object, polymorphic: true
  belongs_to :user
  belongs_to :user_session

  serialize :event_data, JSON
  validate :check_user

  def check_user
    if (user || user_session) && (!user || !user_session)
      errors.add(:user, 'must provide both user and user_session or none')
      errors.add(:user_session, 'must provide both user and user_session or none')
    end
  end
end
