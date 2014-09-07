class ApiToken < ActiveRecord::Base
  belongs_to :user

  validates :user_id, :token, presence: true
  validates :token, length: {is: 100}
end
