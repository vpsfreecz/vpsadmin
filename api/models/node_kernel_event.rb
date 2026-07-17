class NodeKernelEvent < ApplicationRecord
  PUBLIC_EVENT_TYPES = %w[boot reported_release_change livepatch_change].freeze

  belongs_to :node
  belongs_to :kernel_evidence,
             class_name: 'NodeKernelEvidence',
             foreign_key: :node_kernel_evidence_id,
             optional: true
  has_many :sysctl_changes,
           class_name: 'NodeSysctlChange',
           dependent: :delete_all,
           inverse_of: :node_kernel_event
  has_many :software_changes,
           class_name: 'NodeSoftwareChange',
           dependent: :delete_all,
           inverse_of: :node_kernel_event

  enum :event_type, %i[
    boot
    reported_release_change
    livepatch_change
    ebpf_change
    module_change
    sysctl_change
    deployment_change
  ]
  enum :source, %i[reconstructed_node_status node_report]
  enum :confidence, %i[incomplete inferred exact]

  validates :reported_release, :observed_before, presence: true
  validates :source_status_id,
            uniqueness: { scope: %i[node_id event_type] },
            allow_nil: true

  scope :kernel_history, -> { where(event_type: event_types.slice(*PUBLIC_EVENT_TYPES).values) }
end
