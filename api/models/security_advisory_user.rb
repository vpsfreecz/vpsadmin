class SecurityAdvisoryUser < ApplicationRecord
  belongs_to :security_advisory
  belongs_to :user
end

class User
  has_many :security_advisory_users
end
