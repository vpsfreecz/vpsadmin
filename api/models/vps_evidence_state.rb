class VpsEvidenceState < ApplicationRecord
  attribute :target, :json
  belongs_to :vps
  belongs_to :user
  belongs_to :node, optional: true
end
