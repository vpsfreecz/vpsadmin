require 'vpsadmin/api/lifetimes'

class ObjectState < ApplicationRecord
  belongs_to :user
  enum :state, VpsAdmin::API::Lifetimes::STATES

  def self.new_log(obj, state, reason, user, expiration, remind_date)
    new(
      class_name: obj.class.name,
      row_id: obj.id,
      state:,
      reason:,
      user:,
      expiration_date: expiration,
      remind_after_date: remind_date
    )
  end
end
