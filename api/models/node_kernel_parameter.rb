class NodeKernelParameter < ApplicationRecord
  belongs_to :node_kernel_evidence, inverse_of: :kernel_parameters

  validates :name, presence: true
  validates :position,
            numericality: { only_integer: true, greater_than_or_equal_to: 0 },
            uniqueness: { scope: :node_kernel_evidence_id }
end
