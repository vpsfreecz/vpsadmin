class NodeSoftwareVersion < ApplicationRecord
  belongs_to :node_kernel_evidence, inverse_of: :software_versions
  has_one :node, through: :node_kernel_evidence
  delegate :snapshot_type, :snapshot_revision, :observed_at, to: :node_kernel_evidence

  enum :generation, %i[booted current]
  enum :component, %i[vpsadminos vpsadmin nixpkgs system_configuration]
  enum :version_source, { native: 0 }, prefix: :version
  enum :revision_source, { native: 0, confctl: 1 }, prefix: :revision

  validates :generation, :component, presence: true
  validates :component, uniqueness: { scope: %i[node_kernel_evidence_id generation] }
  validates :revision, format: { with: /\A[0-9a-f]{40}\z/ }, allow_nil: true
  validate :sources_match_values

  protected

  def sources_match_values
    errors.add(:version_source, 'must be present with a version') if version.present? != version_source.present?
    if revision.present? != revision_source.present?
      errors.add(:revision_source, 'must be present with a revision')
    end
    return unless revision_dirty && !revision_native?

    errors.add(:revision_dirty, 'is supported only for native revisions')
  end
end
