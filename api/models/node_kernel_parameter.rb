class NodeKernelParameter < ApplicationRecord
  belongs_to :node_kernel_evidence, inverse_of: :kernel_parameters
  has_one :node, through: :node_kernel_evidence
  delegate :snapshot_type, :snapshot_revision, :observed_at, to: :node_kernel_evidence

  validates :name, presence: true
  validates :position,
            numericality: { only_integer: true, greater_than_or_equal_to: 0 },
            uniqueness: { scope: :node_kernel_evidence_id }
end
