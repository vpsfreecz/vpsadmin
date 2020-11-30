class OutageExport < ActiveRecord::Base
  belongs_to :outage
  belongs_to :export
  belongs_to :user
  belongs_to :environment
  belongs_to :location
  belongs_to :node
end

class Export
  has_many :outage_exports
end
