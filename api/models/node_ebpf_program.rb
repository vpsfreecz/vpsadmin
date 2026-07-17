class NodeEbpfProgram < ApplicationRecord
  belongs_to :node_kernel_evidence, inverse_of: :ebpf_programs
  has_one :node, through: :node_kernel_evidence
  delegate :snapshot_type, :snapshot_revision, :observed_at, to: :node_kernel_evidence
  has_many :program_objects,
           class_name: 'NodeEbpfProgramObject',
           dependent: :delete_all,
           inverse_of: :node_ebpf_program
  has_many :program_links,
           class_name: 'NodeEbpfProgramLink',
           dependent: :delete_all,
           inverse_of: :node_ebpf_program

  validates :name, presence: true, uniqueness: { scope: :node_kernel_evidence_id }
  validates :active, inclusion: { in: [true, false] }
end
