class NodeKernelEvidenceError < ApplicationRecord
  belongs_to :node_kernel_evidence, inverse_of: :kernel_evidence_errors

  validates :component, :reason, presence: true
end
