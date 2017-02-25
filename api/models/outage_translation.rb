class OutageTranslation < ActiveRecord::Base
  belongs_to :outage_report
  belongs_to :language
end
