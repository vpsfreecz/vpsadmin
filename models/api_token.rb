class ApiToken < ActiveRecord::Base
  belongs_to :user

  validates :user_id, :token, presence: true
  validates :token, length: {is: 100}

  enum lifetime: %i(fixed renewable_manual renewable_auto permanent)

  def renew
    valid_to = Time.now + interval
  end
end
