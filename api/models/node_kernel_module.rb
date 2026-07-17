class NodeKernelModule < ApplicationRecord
  belongs_to :node_kernel_evidence, inverse_of: :kernel_modules
  has_one :node, through: :node_kernel_evidence
  delegate :snapshot_type, :snapshot_revision, :observed_at, to: :node_kernel_evidence

  validates :name, presence: true, uniqueness: { scope: :node_kernel_evidence_id }
end
