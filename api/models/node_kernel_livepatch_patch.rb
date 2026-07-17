class NodeKernelLivepatchPatch < ApplicationRecord
  belongs_to :node_kernel_livepatch, inverse_of: :patches
  has_one :node_kernel_evidence, through: :node_kernel_livepatch
  has_one :node, through: :node_kernel_evidence
  delegate :snapshot_type, :snapshot_revision, :observed_at, to: :node_kernel_evidence

  validates :name, presence: true, uniqueness: { scope: :node_kernel_livepatch_id }
end
