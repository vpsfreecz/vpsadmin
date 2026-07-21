class SecurityAdvisoryNodeStatus < ApplicationRecord
  belongs_to :security_advisory
  belongs_to :node
  has_many :security_advisory_node_status_translations, dependent: :delete_all

  enum :state, %i[unknown not_affected vulnerable mitigated]

  validates :security_advisory, :node, presence: true
  validates :node_id, uniqueness: { scope: :security_advisory_id }
  validate :node_in_advisory_scope
  validate :mitigated_times_present

  STATE_LABELS = {
    'unknown' => 'Unknown',
    'not_affected' => 'Not affected',
    'vulnerable' => 'Vulnerable',
    'mitigated' => 'Mitigated'
  }.freeze

  def state_label
    STATE_LABELS.fetch(state, state.to_s)
  end

  def update_translations!(translations)
    translations.each do |lang, attrs|
      note_value = attrs[:note].presence
      translation = security_advisory_node_status_translations.find_by(language: lang)

      if note_value
        translation ||= security_advisory_node_status_translations.build(language: lang)
        translation.update!(note: note_value)
      else
        translation&.destroy!
      end
    end

    security_advisory_node_status_translations.reset
    self
  end

  def localized_note(lang)
    translations = security_advisory_node_status_translations
    translation = if translations.loaded?
                    translations.target.find { |row| row.language_id == lang.id }
                  else
                    translations.find_by(language_id: lang.id)
                  end
    translation&.note
  end

  def self.define_note_accessor(lang)
    method_name = "#{lang.code}_note"
    return if method_defined?(method_name)

    define_method(method_name) do
      localized_note(lang)
    end
  end

  # The API resource defines these accessors after the database schema exists.
  # Querying languages while model files are loaded prevents a fresh database
  # from running its first migration.

  protected

  def node_in_advisory_scope
    return if node.nil?
    return if SecurityAdvisory.advisory_nodes.where(id: node.id).exists?

    errors.add(:node, 'must be an active hypervisor or storage node')
  end

  def mitigated_times_present
    return unless mitigated?

    errors.add(:vulnerable_until, 'must be set for mitigated nodes') if vulnerable_until.nil?
    errors.add(:mitigated_since, 'must be set for mitigated nodes') if mitigated_since.nil?
  end
end
