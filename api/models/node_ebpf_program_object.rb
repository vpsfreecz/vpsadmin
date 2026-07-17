class NodeEbpfProgramObject < ApplicationRecord
  belongs_to :node_ebpf_program, inverse_of: :program_objects

  validates :name, presence: true, uniqueness: { scope: :node_ebpf_program_id }
end
