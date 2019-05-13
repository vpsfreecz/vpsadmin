class UserFailedLogin < ActiveRecord::Base
  belongs_to :user
  belongs_to :user_agent
end
