class IntegrityFact < ActiveRecord::Base
  belongs_to :integrity_object
  enum status: %i(false true),
       severity: %i(low normal high)
  serialize :value
end
