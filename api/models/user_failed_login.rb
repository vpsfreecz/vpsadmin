class UserFailedLogin < ApplicationRecord
  belongs_to :user
  belongs_to :user_agent
end
