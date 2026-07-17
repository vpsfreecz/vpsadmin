class NodeKernelModule < ApplicationRecord
  belongs_to :node_kernel_evidence, inverse_of: :kernel_modules

  validates :name, presence: true, uniqueness: { scope: :node_kernel_evidence_id }
end
