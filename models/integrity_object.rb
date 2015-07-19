class IntegrityObject < ActiveRecord::Base
  belongs_to :integrity_check
  enum status: %i(undetermined integral broken)

  has_ancestry cache_depth: true
end
