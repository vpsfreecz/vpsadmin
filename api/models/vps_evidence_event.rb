class VpsEvidenceEvent < ApplicationRecord
  attr_readonly :node_id, :signal, :producer_epoch, :sequence, :part, :parts, :digest, :observed_at, :received_at, :facts, :current_stream
  attribute :facts, :json
  belongs_to :node
end
