class OutageTranslation < ActiveRecord::Base
  belongs_to :outage
  belongs_to :outage_update
  belongs_to :language

  validate :check_parents

  protected
  def check_parents
    if outage_id.nil? && outage_update_id.nil?
      errors.add(:outage_id, 'set outage or outage_update')
      errors.add(:outage_update_id, 'set outage or outage_update')
    end
  end
end
