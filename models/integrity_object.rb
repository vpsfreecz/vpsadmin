class IntegrityObject < ActiveRecord::Base
  belongs_to :integrity_check
  belongs_to :node
  enum status: %i(undetermined integral broken)

  has_ancestry cache_depth: true
end
