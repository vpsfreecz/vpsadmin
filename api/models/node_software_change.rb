class NodeSoftwareChange < ApplicationRecord
  VERSION_SOURCES = %w[native].freeze
  REVISION_SOURCES = %w[native confctl].freeze

  belongs_to :node_kernel_event, inverse_of: :software_changes
  has_one :node, through: :node_kernel_event
  has_one :node_kernel_evidence, through: :node_kernel_event, source: :kernel_evidence
  delegate :observed_after, :observed_before, to: :node_kernel_event

  enum :generation, %i[booted current]
  enum :component, %i[vpsadminos vpsadmin nixpkgs system_configuration]

  validates :generation, :component, presence: true
  validates :component, uniqueness: { scope: %i[node_kernel_event_id generation] }
  validates :before_version_source, :after_version_source,
            inclusion: { in: VERSION_SOURCES }, allow_nil: true
  validates :before_revision_source, :after_revision_source,
            inclusion: { in: REVISION_SOURCES }, allow_nil: true
  validates :before_revision, :after_revision,
            format: { with: /\A[0-9a-f]{40}\z/ }, allow_nil: true
  validate :sources_match_values

  protected

  def sources_match_values
    %w[before after].each do |side|
      version = public_send("#{side}_version")
      version_source = public_send("#{side}_version_source")
      revision = public_send("#{side}_revision")
      revision_source = public_send("#{side}_revision_source")
      revision_dirty = public_send("#{side}_revision_dirty")

      if version.present? != version_source.present?
        errors.add("#{side}_version_source", 'must be present with a version')
      end
      if revision.present? != revision_source.present?
        errors.add("#{side}_revision_source", 'must be present with a revision')
      end
      if revision_dirty && revision_source != 'native'
        errors.add("#{side}_revision_dirty", 'is supported only for native revisions')
      end
    end
  end
end
