class NodeKernelEvidence < ApplicationRecord
  belongs_to :node

  has_many :kernel_parameters,
           class_name: 'NodeKernelParameter',
           dependent: :delete_all,
           inverse_of: :node_kernel_evidence
  has_many :kernel_modules,
           class_name: 'NodeKernelModule',
           dependent: :delete_all,
           inverse_of: :node_kernel_evidence
  has_many :sysctls,
           class_name: 'NodeSysctl',
           dependent: :delete_all,
           inverse_of: :node_kernel_evidence
  has_many :software_versions,
           class_name: 'NodeSoftwareVersion',
           dependent: :delete_all,
           inverse_of: :node_kernel_evidence
  has_many :kernel_livepatches,
           class_name: 'NodeKernelLivepatch',
           dependent: :destroy,
           inverse_of: :node_kernel_evidence
  has_many :ebpf_programs,
           class_name: 'NodeEbpfProgram',
           dependent: :destroy,
           inverse_of: :node_kernel_evidence
  has_many :kernel_evidence_errors,
           class_name: 'NodeKernelEvidenceError',
           dependent: :delete_all,
           inverse_of: :node_kernel_evidence

  enum :snapshot_type, %i[current event]

  validates :snapshot_type, :report_schema_version, :observed_at, :received_at, presence: true
  validates :snapshot_revision,
            presence: true,
            format: { with: /\A[0-9a-f]{64}\z/ }
  validate :event_snapshots_are_immutable, on: :update

  protected

  def event_snapshots_are_immutable
    errors.add(:base, 'event evidence snapshots are immutable') if event?
  end
end
