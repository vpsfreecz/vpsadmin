class OutageTranslation < ActiveRecord::Base
  belongs_to :outage
  belongs_to :outage_report
  belongs_to :language

  validate :check_parents

  protected
  def check_parents
    if outage_id.nil? && outage_report_id.nil?
      errors.add(:outage_id, 'set outage or outage_report')
      errors.add(:outage_report_id, 'set outage or outage_report')
    end
  end
end
