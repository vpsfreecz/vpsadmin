class NodeEbpfProgramLink < ApplicationRecord
  belongs_to :node_ebpf_program, inverse_of: :program_links

  validates :name, presence: true, uniqueness: { scope: :node_ebpf_program_id }
  validates :attached, inclusion: { in: [true, false] }
end
