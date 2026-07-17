class NodeKernelLivepatchPatch < ApplicationRecord
  belongs_to :node_kernel_livepatch, inverse_of: :patches

  validates :name, presence: true, uniqueness: { scope: :node_kernel_livepatch_id }
end
