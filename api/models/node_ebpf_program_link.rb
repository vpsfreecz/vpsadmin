class NodeEbpfProgramLink < ApplicationRecord
  belongs_to :node_ebpf_program, inverse_of: :program_links
  has_one :node_kernel_evidence, through: :node_ebpf_program
  has_one :node, through: :node_kernel_evidence
  delegate :snapshot_type, :snapshot_revision, :observed_at, to: :node_kernel_evidence

  validates :name, presence: true, uniqueness: { scope: :node_ebpf_program_id }
  validates :attached, inclusion: { in: [true, false] }
end
