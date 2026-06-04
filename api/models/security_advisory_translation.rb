class SecurityAdvisoryTranslation < ApplicationRecord
  belongs_to :security_advisory, optional: true
  belongs_to :security_advisory_update, optional: true
  belongs_to :language

  validates :language, presence: true
  validate :belongs_to_advisory_or_update

  protected

  def belongs_to_advisory_or_update
    if security_advisory_id.present? ^ security_advisory_update_id.present?
      errors.add(:security_advisory, 'must exist') if security_advisory_id.present? && security_advisory.nil?
      errors.add(:security_advisory_update, 'must exist') if security_advisory_update_id.present? && security_advisory_update.nil?
      return
    end

    errors.add(:base, 'must belong either to advisory or update')
  end
end
