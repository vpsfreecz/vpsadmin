class OutageUpdate < ActiveRecord::Base
  belongs_to :outage
  belongs_to :reported_by, class_name: 'User'
  has_many :outage_translations

  enum state: %i(staged announced closed cancelled)
  enum outage_type: %i(tbd restart reset network performance maintenance)
end
