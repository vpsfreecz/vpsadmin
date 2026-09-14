class NodeKernelEvidenceCheckpoint < ApplicationRecord
  belongs_to :node

  serialize :report, coder: JSON

  validates :report, :observed_at, presence: true

  def comparison_report
    VpsAdmin::API::KernelEvidence::Report.from_hash(report)
  end
end
