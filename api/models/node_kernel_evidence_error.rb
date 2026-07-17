class NodeKernelEvidenceError < ApplicationRecord
  belongs_to :node_kernel_evidence, inverse_of: :kernel_evidence_errors
  has_one :node, through: :node_kernel_evidence
  delegate :snapshot_type, :snapshot_revision, :observed_at, to: :node_kernel_evidence

  validates :component, :reason, presence: true
end
