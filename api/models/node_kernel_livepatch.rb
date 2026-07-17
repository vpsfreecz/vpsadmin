class NodeKernelLivepatch < ApplicationRecord
  belongs_to :node_kernel_evidence, inverse_of: :kernel_livepatches
  has_one :node, through: :node_kernel_evidence
  delegate :snapshot_type, :snapshot_revision, :observed_at, to: :node_kernel_evidence
  has_many :patches,
           class_name: 'NodeKernelLivepatchPatch',
           dependent: :delete_all,
           inverse_of: :node_kernel_livepatch

  validates :livepatch_id,
            presence: true,
            uniqueness: { scope: :node_kernel_evidence_id }
end
