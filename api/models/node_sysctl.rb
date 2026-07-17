class NodeSysctl < ApplicationRecord
  belongs_to :node_kernel_evidence, inverse_of: :sysctls

  validates :name, presence: true, uniqueness: { scope: :node_kernel_evidence_id }
  validates :available, inclusion: { in: [true, false] }
end
