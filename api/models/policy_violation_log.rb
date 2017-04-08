class PolicyViolationLog < ActiveRecord::Base
  belongs_to :policy_violation
  serialize :value
end
